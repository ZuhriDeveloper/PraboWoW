<#
    Minimal WDB2 (.db2) reader for the 4.3.4 client files in server/data/dbc/.

    Dot-source this file; do not run it directly:

        . (Join-Path $PSScriptRoot 'lib\Db2.ps1')

    Why this exists: item data for 4.3.4 does NOT live in the world database. The core
    reads Item.db2 and Item-sparse.db2 from the extracted client data, and the
    `hotfixes`.`item` / `item_sparse` tables hold only server-side ADDITIONS pushed to
    clients (208 rows against the client file's 54086). Any audit that queries the
    hotfixes tables alone sees under half a percent of the items that exist.

    Two layout traps cost real time here and are why this is a shared helper rather
    than inline code:

    1. When maxId > 0 the header is followed by an index block of
       (maxId - minId + 1) * 6 bytes. That block is NOT an offset/size map -- seeking
       through it as one yields garbage. Records are stored sequentially starting at
       48 + indexBlockSize, sorted ascending by id, every record exactly recordSize
       bytes. When maxId == 0 there is no index block and records start at 48.

    2. Every field in these two files is 4 bytes wide (recordSize / 4 == fieldCount),
       so a record is a flat uint32 array. String fields hold a byte offset into the
       string table, which begins after the last record. Offset 0 means empty string.

    The field ORDER matches the column order of the matching `hotfixes` table, minus
    TrinityCore's trailing bookkeeping column `VerifiedBuild`. That is the cheapest
    way to re-derive indices if a field is ever needed that this file does not expose:

        SELECT ORDINAL_POSITION, COLUMN_NAME FROM information_schema.columns
        WHERE table_schema='hotfixes' AND table_name='item_sparse'
        ORDER BY ORDINAL_POSITION;   -- field index = ORDINAL_POSITION - 1

    The record walk itself is compiled C# rather than PowerShell. These two files hold
    roughly 119000 records between them, and a Windows PowerShell 5.1 loop over that
    takes minutes; the same walk in C# takes well under a second. The interpreter
    overhead, not the I/O, is the entire cost.
#>

if (-not ('PraboWoW.Db2Reader' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Text;

namespace PraboWoW
{
    public class Db2Layout
    {
        public uint RecordCount;
        public uint FieldCount;
        public uint RecordSize;
        public uint Build;
        public int  DataStart;
        public int  StringTableStart;
    }

    public class ItemUse
    {
        public uint   ItemId;
        public uint   Spell;
        public string Name;
        public uint   Area;
        public int    Map;
    }

    public static class Db2Reader
    {
        public static Db2Layout ReadHeader(byte[] b)
        {
            string magic = Encoding.ASCII.GetString(b, 0, 4);
            if (magic != "WDB2")
                throw new Exception("not a WDB2 file (magic was '" + magic + "')");

            var L = new Db2Layout();
            L.RecordCount   = BitConverter.ToUInt32(b, 4);
            L.FieldCount    = BitConverter.ToUInt32(b, 8);
            L.RecordSize    = BitConverter.ToUInt32(b, 12);
            uint strSize    = BitConverter.ToUInt32(b, 16);
            L.Build         = BitConverter.ToUInt32(b, 24);
            uint minId      = BitConverter.ToUInt32(b, 32);
            uint maxId      = BitConverter.ToUInt32(b, 36);

            if (L.RecordSize != L.FieldCount * 4)
                throw new Exception("unexpected layout: recordSize " + L.RecordSize +
                                    " is not fieldCount " + L.FieldCount + " * 4");

            long indexBytes = (maxId > 0) ? ((long)(maxId - minId + 1) * 6) : 0;
            L.DataStart        = (int)(48 + indexBytes);
            L.StringTableStart = (int)(L.DataStart + (long)L.RecordCount * L.RecordSize);

            long expected = (long)L.StringTableStart + strSize;
            if (expected != b.LongLength)
                throw new Exception("layout mismatch: computed size " + expected +
                                    " but file is " + b.LongLength + " bytes");
            return L;
        }

        public static string ReadString(byte[] b, int stringTableStart, uint offset)
        {
            if (offset == 0) return "";
            int start = stringTableStart + (int)offset;
            if (start >= b.Length) return "";
            int end = start;
            while (end < b.Length && b[end] != 0) end++;
            return Encoding.UTF8.GetString(b, start, end - start);
        }

        // Collects the ids whose value at fieldIndex equals wanted. Used to pull the
        // quest-class item ids out of Item.db2 without materialising all 64775.
        public static HashSet<uint> CollectIdsWhere(byte[] b, Db2Layout L, int fieldIndex, uint wanted)
        {
            var set = new HashSet<uint>();
            for (int i = 0; i < L.RecordCount; i++)
            {
                int o = L.DataStart + i * (int)L.RecordSize;
                if (BitConverter.ToUInt32(b, o + fieldIndex * 4) == wanted)
                    set.Add(BitConverter.ToUInt32(b, o));
            }
            return set;
        }

        // Walks Item-sparse.db2 and returns the records that cast a spell on use and
        // whose id is in allowedIds.
        public static List<ItemUse> CollectOnUseItems(
            byte[] b, Db2Layout L, HashSet<uint> allowedIds,
            int fSpell, int fTrigger, int fName, int fArea, int fMap, int onUseValue)
        {
            var list = new List<ItemUse>();
            for (int i = 0; i < L.RecordCount; i++)
            {
                int o = L.DataStart + i * (int)L.RecordSize;

                uint spell = BitConverter.ToUInt32(b, o + fSpell * 4);
                if (spell == 0) continue;
                if (BitConverter.ToInt32(b, o + fTrigger * 4) != onUseValue) continue;

                uint id = BitConverter.ToUInt32(b, o);
                if (!allowedIds.Contains(id)) continue;

                var r = new ItemUse();
                r.ItemId = id;
                r.Spell  = spell;
                r.Name   = ReadString(b, L.StringTableStart, BitConverter.ToUInt32(b, o + fName * 4));
                r.Area   = BitConverter.ToUInt32(b, o + fArea * 4);
                r.Map    = BitConverter.ToInt32(b, o + fMap * 4);
                list.Add(r);
            }
            return list;
        }
    }
}
'@
}
