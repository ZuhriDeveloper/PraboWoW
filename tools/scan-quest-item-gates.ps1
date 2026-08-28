<#
.SYNOPSIS
    Audits quest items whose "Use" spell has no server-side restriction, and generates
    the SQL that ties those spells to the quest they belong to.

.DESCRIPTION
    A quest item in TrinityCore is only restricted by rows in the world database. The
    core has no innate idea that a given item is meant for one NPC in one zone. Where
    those rows are missing the item casts on anything, anywhere, for anyone holding
    it -- which is the abuse vector this script closes.

    TDB 434.22011 leaves most of that data empty for 4.3.4, so the gap is wide. Two
    tables carry the restriction:

      conditions type 17 (CONDITION_SOURCE_TYPE_SPELL)
        Gates whether the spell may be cast at all. Paired with condition type 9
        (CONDITION_QUESTTAKEN) it means "only while this quest is in your log".

      conditions type 13 (CONDITION_SOURCE_TYPE_SPELL_IMPLICIT_TARGET)
        Gates what the spell may hit. Needs the intended creature entry.

    This script generates the type 17 half ONLY, and only where the item-to-quest link
    can be established from quest_template. That link is derivable; the intended target
    creature is not -- nothing in the client data or the world database records that
    spell X was designed to hit NPC Y. Those rows need a human with a quest database,
    so the script reports them rather than guessing. A wrong type 13 row is worse than
    a missing one: it makes a working quest uncompletable.

    Items that are ever handed out as a quest REWARD are excluded outright. Those stay
    in the bags after the quest is turned in, so gating them behind an active quest
    would break them permanently.

    The scan itself is read-only. Nothing touches the database unless -Apply is passed.

.PARAMETER DbcDir
    Extracted client data. Item data for 4.3.4 lives here, NOT in the world database;
    the hotfixes tables hold only server-side additions and are merged on top.

.PARAMETER OutDir
    Where the generated .sql and the audit .csv are written. Defaults to sql/ at the
    repository root -- deliberately NOT core/sql/, which is a pinned submodule whose
    custom/ subtree is gitignored (CLAUDE.md rules #1 and #2).

.PARAMETER MaxQuestsPerSpell
    Skip any spell shared by more than this many quests. A high count means the item is
    generic rather than quest-scoped, and gating it would be wrong.

.PARAMETER Apply
    Run the generated SQL against the world database. Without this the script only
    writes files and prints a summary.

.EXAMPLE
    .\tools\scan-quest-item-gates.ps1
    Audit only. Writes sql/world/<stamp>_quest_item_quest_gate.sql and the report.

.EXAMPLE
    .\tools\scan-quest-item-gates.ps1 -Apply
    Audit, generate, and apply. Follow with `.reload conditions` on a running server.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $MySqlDir          = 'C:\MySQL\MySQL Server 8.0',
    [string] $DbHost            = '127.0.0.1',
    [int]    $Port              = 3306,
    [string] $DbUser            = 'trinity',
    [string] $DbPassword        = 'trinity',
    [string] $DbcDir,
    [string] $OutDir,
    [int]    $MaxQuestsPerSpell = 6,
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not reliably populated while param() defaults are being bound under
# `powershell -File`, so the paths are resolved here instead.
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = Split-Path -Parent $scriptDir

. (Join-Path $scriptDir 'lib\Db2.ps1')

if (-not $DbcDir) { $DbcDir = Join-Path $repoRoot 'server\data\dbc\enUS' }
if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'sql\world' }

$DbcDir = [System.IO.Path]::GetFullPath($DbcDir)
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
$mysql  = Join-Path $MySqlDir 'bin\mysql.exe'

if (-not (Test-Path $mysql))  { throw "mysql.exe not found at $mysql. Run tools\bootstrap-db.ps1 first." }
if (-not (Test-Path $DbcDir)) { throw "client data not found at $DbcDir. Run tools\extract-client-data.ps1 first." }

# Field indices into Item-sparse.db2. See tools/lib/Db2.ps1 for how to re-derive these
# from the hotfixes.item_sparse column order if a new field is ever needed.
$SPARSE_SPELL1  = 68
$SPARSE_TRIGGER = 73
$SPARSE_NAME    = 99
$SPARSE_AREA    = 114
$SPARSE_MAP     = 115

$ITEM_CLASS = 1     # index into Item.db2
$CLASS_QUEST      = 12   # ItemClass::Quest
$TRIGGER_ON_USE   = 0    # ITEM_SPELLTRIGGER_ON_USE
$SRC_TYPE_SPELL   = 17   # CONDITION_SOURCE_TYPE_SPELL
$COND_QUESTTAKEN  = 9    # CONDITION_QUESTTAKEN

function Invoke-MySqlTsv {
    <#
    .SYNOPSIS
        Runs a read-only query and returns its rows as string arrays (tab-separated).
    #>
    param([Parameter(Mandatory = $true)][string] $Query)

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw = $Query | & $mysql "-u$DbUser" "-p$DbPassword" "-h$DbHost" "-P$Port" '-N' '--batch' 2>$null
        if ($LASTEXITCODE -ne 0) { throw "mysql query failed with exit code $LASTEXITCODE" }
    } finally {
        $ErrorActionPreference = $previous
    }

    $rows = New-Object System.Collections.ArrayList
    foreach ($line in $raw) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        [void]$rows.Add($line -split "`t")
    }
    return $rows
}

function Add-ToSet {
    <#
    .SYNOPSIS
        Adds a positive id to a set, ignoring blanks and non-positive values.

    .DESCRIPTION
        `conditions`.`SourceEntry` is signed, and a NEGATIVE value there is a reference
        to a shared condition group rather than a spell id. Coercing those to uint32
        throws, so they are dropped here along with zeroes.
    #>
    param([hashtable] $Set, $Key)

    if ([string]::IsNullOrWhiteSpace([string]$Key)) { return }
    $k = 0L
    if (-not [int64]::TryParse([string]$Key, [ref]$k)) { return }
    if ($k -le 0) { return }
    $Set[[uint32]$k] = $true
}

Write-Host ''
Write-Host 'Reading client item data (this walks ~120k records; allow a minute)...'

# --- Item.db2 : id -> ClassID -------------------------------------------------------
$itemBytes  = [System.IO.File]::ReadAllBytes((Join-Path $DbcDir 'Item.db2'))
$itemHeader = [PraboWoW.Db2Reader]::ReadHeader($itemBytes)
$questClassIds = [PraboWoW.Db2Reader]::CollectIdsWhere($itemBytes, $itemHeader, $ITEM_CLASS, $CLASS_QUEST)

$sparseBytes  = [System.IO.File]::ReadAllBytes((Join-Path $DbcDir 'Item-sparse.db2'))
$sparseHeader = [PraboWoW.Db2Reader]::ReadHeader($sparseBytes)
$onUse = [PraboWoW.Db2Reader]::CollectOnUseItems(
    $sparseBytes, $sparseHeader, $questClassIds,
    $SPARSE_SPELL1, $SPARSE_TRIGGER, $SPARSE_NAME, $SPARSE_AREA, $SPARSE_MAP, $TRIGGER_ON_USE)

$candidates = @{}   # itemId -> record
foreach ($r in $onUse) {
    $candidates[$r.ItemId] = [pscustomobject]@{
        ItemId = $r.ItemId
        Spell  = $r.Spell
        Name   = $r.Name
        Area   = $r.Area
        Map    = $r.Map
        Source = 'client'
    }
}

Write-Host ("  Item.db2         {0,6} items ({1} quest class)" -f $itemHeader.RecordCount, $questClassIds.Count)
Write-Host ("  Item-sparse.db2  {0,6} items" -f $sparseHeader.RecordCount)

# --- hotfixes additions: items the client file does not carry ----------------------
$hotfixRows = Invoke-MySqlTsv -Query @"
SELECT s.ID, s.SpellID1, COALESCE(s.Display,''), s.AreaID, s.MapID
FROM hotfixes.item_sparse s JOIN hotfixes.item i ON i.ID = s.ID
WHERE i.ClassID = $CLASS_QUEST AND s.SpellID1 > 0 AND s.SpellTrigger1 = $TRIGGER_ON_USE;
"@
foreach ($r in $hotfixRows) {
    $id = [uint32]$r[0]
    $candidates[$id] = [pscustomobject]@{
        ItemId = $id
        Spell  = [uint32]$r[1]
        Name   = $r[2]
        Area   = [uint32]$r[3]
        Map    = [int]$r[4]
        Source = 'hotfix'
    }
}
Write-Host ("  hotfixes overlay {0,6} quest items merged" -f $hotfixRows.Count)
Write-Host ("  -> {0} quest-class items cast a spell on use" -f $candidates.Count)

# --- what already has some form of server-side gating ------------------------------
Write-Host ''
Write-Host 'Reading world database...'

$gated = @{}
foreach ($r in (Invoke-MySqlTsv -Query "SELECT DISTINCT SourceEntry FROM world.conditions WHERE SourceTypeOrReferenceId IN (13,17);")) {
    Add-ToSet $gated $r[0]
}
foreach ($r in (Invoke-MySqlTsv -Query "SELECT DISTINCT spell_id FROM world.spell_script_names;")) {
    Add-ToSet $gated $r[0]
}
foreach ($r in (Invoke-MySqlTsv -Query "SELECT DISTINCT event_param1 FROM world.smart_scripts WHERE event_type = 8 AND event_param1 > 0;")) {
    Add-ToSet $gated $r[0]
}

# Roles an item can play in a quest. Only the quest-scoped ones justify a QUESTTAKEN
# gate; reward roles mean the player keeps the item after turn-in.
$scopedOf = @{}   # itemId -> hashtable of questId
$rewardItems = @{}

# The unpivot and grouping happen in SQL. Doing it in PowerShell means iterating
# quest_template x 12 columns cell by cell, which is an order of magnitude more
# interpreter work than the few thousand grouped rows that come back this way.
foreach ($r in (Invoke-MySqlTsv -Query @"
SELECT item, GROUP_CONCAT(DISTINCT quest ORDER BY quest SEPARATOR ' ')
FROM (
    SELECT RequiredItemId1 AS item, ID AS quest FROM world.quest_template
    UNION ALL SELECT RequiredItemId2, ID FROM world.quest_template
    UNION ALL SELECT RequiredItemId3, ID FROM world.quest_template
    UNION ALL SELECT RequiredItemId4, ID FROM world.quest_template
    UNION ALL SELECT RequiredItemId5, ID FROM world.quest_template
    UNION ALL SELECT RequiredItemId6, ID FROM world.quest_template
    UNION ALL SELECT ItemDrop1,       ID FROM world.quest_template
    UNION ALL SELECT ItemDrop2,       ID FROM world.quest_template
    UNION ALL SELECT ItemDrop3,       ID FROM world.quest_template
    UNION ALL SELECT ItemDrop4,       ID FROM world.quest_template
    UNION ALL SELECT StartItem,       ID FROM world.quest_template
) t
WHERE item > 0
GROUP BY item;
"@)) {
    $item = [uint32]$r[0]
    $set = @{}
    foreach ($q in ($r[1] -split ' ')) {
        if ([string]::IsNullOrWhiteSpace($q)) { continue }
        $set[[uint32]$q] = $true
    }
    $scopedOf[$item] = $set
}

foreach ($r in (Invoke-MySqlTsv -Query @"
SELECT DISTINCT item FROM (
    SELECT RewardItem1 AS item FROM world.quest_template
    UNION ALL SELECT RewardItem2 FROM world.quest_template
    UNION ALL SELECT RewardItem3 FROM world.quest_template
    UNION ALL SELECT RewardItem4 FROM world.quest_template
    UNION ALL SELECT RewardChoiceItemID1 FROM world.quest_template
    UNION ALL SELECT RewardChoiceItemID2 FROM world.quest_template
    UNION ALL SELECT RewardChoiceItemID3 FROM world.quest_template
    UNION ALL SELECT RewardChoiceItemID4 FROM world.quest_template
    UNION ALL SELECT RewardChoiceItemID5 FROM world.quest_template
    UNION ALL SELECT RewardChoiceItemID6 FROM world.quest_template
) t WHERE item > 0;
"@)) {
    Add-ToSet $rewardItems $r[0]
}

# --- classify -----------------------------------------------------------------------
# Grouping is by SPELL, not by item: several items can share one spell, and a single
# conditions row governs the spell for all of them.
$bySpell = @{}
$report  = New-Object System.Collections.ArrayList

foreach ($item in $candidates.Values) {
    $verdict = ''
    if ($gated.ContainsKey($item.Spell)) {
        $verdict = 'already-gated'
    } elseif ($rewardItems.ContainsKey($item.ItemId)) {
        $verdict = 'skip-reward-item'
    } elseif (-not $scopedOf.ContainsKey($item.ItemId)) {
        $verdict = 'manual-no-quest-link'
    } else {
        $verdict = 'auto-quest-gate'
        if (-not $bySpell.ContainsKey($item.Spell)) {
            $bySpell[$item.Spell] = [pscustomobject]@{
                Spell   = $item.Spell
                Quests  = @{}
                Items   = New-Object System.Collections.ArrayList
                Poisoned = $false
            }
        }
        $g = $bySpell[$item.Spell]
        [void]$g.Items.Add($item)
        foreach ($q in $scopedOf[$item.ItemId].Keys) { $g.Quests[$q] = $true }
    }

    [void]$report.Add([pscustomobject]@{
        ItemId  = $item.ItemId
        Name    = $item.Name
        Spell   = $item.Spell
        Source  = $item.Source
        Area    = $item.Area
        Map     = $item.Map
        Quests  = if ($scopedOf.ContainsKey($item.ItemId)) { ($scopedOf[$item.ItemId].Keys | Sort-Object) -join ' ' } else { '' }
        Verdict = $verdict
    })
}

# Index by spell once. Scanning $candidates and $report per spell instead turns this
# into an O(spells x items) sweep, which on this data set is millions of iterations.
$itemsBySpell  = @{}
foreach ($item in $candidates.Values) {
    if (-not $itemsBySpell.ContainsKey($item.Spell)) { $itemsBySpell[$item.Spell] = New-Object System.Collections.ArrayList }
    [void]$itemsBySpell[$item.Spell].Add($item)
}
$reportBySpell = @{}
foreach ($row in $report) {
    if (-not $reportBySpell.ContainsKey($row.Spell)) { $reportBySpell[$row.Spell] = New-Object System.Collections.ArrayList }
    [void]$reportBySpell[$row.Spell].Add($row)
}

# A conditions row keys on the SPELL, so it governs every item that casts that spell.
# Gating is therefore only safe when EVERY such item is quest-scoped. One shared spell
# is enough to break an unrelated item: spell 12346 is cast by both Egg of Hakkar (a
# quest item) and Yeh'kinya's Scroll (which has no quest link), and gating it on the
# egg's quest would leave the scroll permanently uncastable.
foreach ($g in $bySpell.Values) {
    foreach ($item in $itemsBySpell[$g.Spell]) {
        if ($rewardItems.ContainsKey($item.ItemId))   { $g.Poisoned = $true }
        if (-not $scopedOf.ContainsKey($item.ItemId)) { $g.Poisoned = $true }
    }
}

$emit = New-Object System.Collections.ArrayList
foreach ($g in ($bySpell.Values | Sort-Object Spell)) {
    $verdict = ''
    if ($g.Poisoned) {
        $verdict = 'skip-spell-shared'
    } elseif ($g.Quests.Count -gt $MaxQuestsPerSpell) {
        $verdict = 'manual-too-many-quests'
    } else {
        [void]$emit.Add($g)
        continue
    }
    foreach ($row in $reportBySpell[$g.Spell]) { $row.Verdict = $verdict }
}

# --- write output -------------------------------------------------------------------
if (-not (Test-Path $OutDir)) { [void](New-Item -ItemType Directory -Force -Path $OutDir) }

$stamp   = Get-Date -Format 'yyyy_MM_dd_HH_mm'
$sqlPath = Join-Path $OutDir "${stamp}_quest_item_quest_gate.sql"
$csvPath = Join-Path $OutDir 'quest-item-audit.csv'

$sql = New-Object System.Collections.ArrayList
[void]$sql.Add("-- Generated by tools/scan-quest-item-gates.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sql.Add('--')
[void]$sql.Add('-- Restricts quest-item "Use" spells to the quest they belong to, so the item')
[void]$sql.Add('-- cannot be fired outside that quest. Target restriction (conditions type 13)')
[void]$sql.Add('-- is NOT generated here: the intended creature is not recorded anywhere local.')
[void]$sql.Add('-- See quest-item-audit.csv for the items still needing that by hand.')
[void]$sql.Add('')

foreach ($g in $emit) {
    $names = ($g.Items | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ', '
    if ($names.Length -gt 120) { $names = $names.Substring(0, 117) + '...' }

    [void]$sql.Add("-- $names (spell $($g.Spell))")
    [void]$sql.Add("DELETE FROM ``conditions`` WHERE ``SourceTypeOrReferenceId``=$SRC_TYPE_SPELL AND ``SourceEntry``=$($g.Spell);")
    [void]$sql.Add("INSERT INTO ``conditions`` (``SourceTypeOrReferenceId``, ``SourceGroup``, ``SourceEntry``, ``SourceId``, ``ElseGroup``, ``ConditionTypeOrReference``, ``ConditionTarget``, ``ConditionValue1``, ``ConditionValue2``, ``ConditionValue3``, ``NegativeCondition``, ``ErrorType``, ``ErrorTextId``, ``ScriptName``, ``Comment``) VALUES")

    # Separate ElseGroups are OR-ed, so several quests mean "any of these is enough".
    $values = New-Object System.Collections.ArrayList
    $elseGroup = 0
    foreach ($q in ($g.Quests.Keys | Sort-Object)) {
        $comment = "$names - only while quest $q is active"
        if ($comment.Length -gt 250) { $comment = $comment.Substring(0, 250) }
        $comment = $comment.Replace("'", "''")
        [void]$values.Add("($SRC_TYPE_SPELL, 0, $($g.Spell), 0, $elseGroup, $COND_QUESTTAKEN, 0, $q, 0, 0, 0, 0, 0, '', '$comment')")
        $elseGroup++
    }
    [void]$sql.Add(($values -join ",`r`n") + ';')
    [void]$sql.Add('')
}

# Written without a BOM on purpose: Set-Content -Encoding UTF8 emits one under
# Windows PowerShell 5.1, and mysql treats those three leading bytes as the start of a
# statement rather than skipping them, so the first line fails to parse.
[System.IO.File]::WriteAllText($sqlPath, ($sql -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
$report | Sort-Object Verdict, Spell | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

# --- summary ------------------------------------------------------------------------
$counts = $report | Group-Object Verdict | Sort-Object Count -Descending

Write-Host ''
Write-Host 'Audit'
Write-Host '-----'
foreach ($c in $counts) {
    Write-Host ("  {0,-24} {1,5} items" -f $c.Name, $c.Count)
}
Write-Host ''
Write-Host ("  generated {0} conditions rows across {1} spells" -f `
    (($emit | ForEach-Object { $_.Quests.Count }) | Measure-Object -Sum).Sum, $emit.Count)
Write-Host ''
Write-Host "  sql    $sqlPath"
Write-Host "  report $csvPath"

if (-not $Apply) {
    Write-Host ''
    Write-Host '  Nothing was written to the database. Re-run with -Apply to load it.'
    Write-Host ''
    return
}

if (-not $PSCmdlet.ShouldProcess('world database', "apply $([System.IO.Path]::GetFileName($sqlPath))")) { return }

Write-Host ''
Write-Host 'Applying to world database...'
$previous = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    Get-Content -Path $sqlPath -Raw | & $mysql "-u$DbUser" "-p$DbPassword" "-h$DbHost" "-P$Port" 'world' 2>$null
    if ($LASTEXITCODE -ne 0) { throw "applying $sqlPath failed with exit code $LASTEXITCODE" }
} finally {
    $ErrorActionPreference = $previous
}
Write-Host '  done. Run `.reload conditions` on a running server to pick it up.'
Write-Host ''
