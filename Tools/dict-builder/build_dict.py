#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
dict-builder: 从 ECDICT CSV + 开源词表构建多词库 words.sqlite

13 个词库：
    小学/初中/高中/考研/专四/专八 来自 mahavivo/english-wordlists 词表 txt
    四级/六级/雅思/托福/GRE      来自 ECDICT 考纲标签 (cet4/cet6/ielts/toefl/gre)
    BEC/PTE                      暂以雅思词表近似（可后续替换真实词表）

用法:
    python3 build_dict.py <ecdict.csv 路径> <输出 sqlite 路径>
"""
import csv
import re
import sqlite3
import sys
from pathlib import Path

# 词库定义：(key, 显示名, 顺序, 来源)
# 来源: "tag:cet4" 表示 ECDICT 标签; "file:xiaoxue.txt" 表示 data/wordlists 下的词表
COLLECTIONS = [
    ("xiaoxue", "小学", 1, "file:xiaoxue.txt"),
    ("chuzhong", "初中", 2, "file:zhongkao.txt"),
    ("gaozhong", "高中", 3, "file:gaozhong.txt"),
    ("cet4", "四级", 4, "tag:cet4"),
    ("kaoyan", "考研", 5, "file:kaoyan.txt"),
    ("cet6", "六级", 6, "tag:cet6"),
    ("tem4", "专四", 7, "file:zhuansi.txt"),
    ("ielts", "雅思", 8, "tag:ielts"),
    ("toefl", "托福", 9, "tag:toefl"),
    ("tem8", "专八", 10, "file:zhuanba.txt"),
    ("bec", "BEC", 11, "tag:ielts"),      # 近似：商务英语暂用雅思词表
    ("gre", "GRE", 12, "tag:gre"),
    ("pte", "PTE", 13, "tag:ielts"),      # 近似：PTE 暂用雅思词表
]

SCHEMA = """
CREATE TABLE word (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    headword TEXT NOT NULL UNIQUE,
    phonetic TEXT,
    definition_cn TEXT,
    definition_en TEXT,
    pos TEXT,
    tags TEXT,
    frequency INTEGER,
    collins INTEGER,
    oxford INTEGER,
    exchange TEXT
);
CREATE INDEX idx_word_frequency ON word(frequency);

CREATE TABLE collection (
    id INTEGER PRIMARY KEY,
    key TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    sort_order INTEGER NOT NULL
);
CREATE TABLE collection_word (
    collection_id INTEGER NOT NULL,
    word_id INTEGER NOT NULL,
    PRIMARY KEY (collection_id, word_id)
);
CREATE INDEX idx_collection_word_word ON collection_word(word_id);
"""

WORD_RE = re.compile(r"[a-zA-Z'\-]+")


def parse_int(value):
    try:
        n = int(value)
        return n if n > 0 else None
    except (TypeError, ValueError):
        return None


def parse_wordlist(path: Path) -> set:
    """解析词表 txt：每行取第一个英文单词（去音标/释义），小写去重"""
    words = set()
    with open(path, encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            m = WORD_RE.search(line)
            if m:
                w = m.group(0).strip("'-").lower()
                if w and w.isalpha():
                    words.add(w)
    return words


def main():
    if len(sys.argv) < 3:
        sys.exit("用法: python3 build_dict.py <ecdict.csv> <输出.sqlite>")
    csv_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    if not csv_path.exists():
        sys.exit(f"找不到 CSV: {csv_path}")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()

    base_dir = Path(__file__).parent / "data" / "wordlists"

    # 1. 收集各词库 headword 集合（txt 词表）
    file_words = {}     # key -> set(headword)
    tag_keys = {}       # key -> tag
    for key, name, order, source in COLLECTIONS:
        if source.startswith("file:"):
            p = base_dir / source[5:]
            file_words[key] = parse_wordlist(p)
            print(f"词表 {key}: {len(file_words[key])} 词")
        elif source.startswith("tag:"):
            tag_keys[key] = source[4:]

    wanted_tags = set(tag_keys.values())
    wanted_file_words = set()
    for s in file_words.values():
        wanted_file_words |= s

    # 2. 流式扫描 ECDICT，收集命中词
    word_rows = {}      # headword -> (row, belongs_to: set of collection keys)
    csv.field_size_limit(20 * 1024 * 1024)
    total = 0
    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            total += 1
            headword = (row.get("word") or "").strip()
            if not headword or " " in headword:
                continue
            low = headword.lower()
            tags = (row.get("tag") or "").split()
            belongs = set()
            for key, tag in tag_keys.items():
                if tag in tags:
                    belongs.add(key)
            if low in wanted_file_words:
                for key, s in file_words.items():
                    if low in s:
                        belongs.add(key)
            if belongs:
                word_rows[low] = (row, belongs)

    print(f"扫描 {total} 行, 命中词 {len(word_rows)} 个")

    # 3. 写入数据库
    conn = sqlite3.connect(out_path)
    conn.executescript(SCHEMA)

    for key, name, order, _ in COLLECTIONS:
        conn.execute("INSERT INTO collection (id, key, name, sort_order) VALUES (?,?,?,?)",
                     (order, key, name, order))

    word_id_of = {}
    for low, (row, belongs) in word_rows.items():
        translation = (row.get("translation") or "").replace("\\n", "\n").strip()
        if not translation:
            continue
        headword = (row.get("word") or "").strip()
        cur = conn.execute(
            "INSERT INTO word (headword, phonetic, definition_cn, definition_en, pos, tags, frequency, collins, oxford, exchange)"
            " VALUES (?,?,?,?,?,?,?,?,?,?)",
            (
                headword,
                (row.get("phonetic") or "").strip() or None,
                translation,
                (row.get("definition") or "").replace("\\n", "\n").strip() or None,
                (row.get("pos") or "").strip() or None,
                " ".join((row.get("tag") or "").split()),
                parse_int(row.get("frq")),
                parse_int(row.get("collins")),
                parse_int(row.get("oxford")),
                (row.get("exchange") or "").strip() or None,
            ),
        )
        word_id_of[low] = cur.lastrowid
        for key in belongs:
            order = next(o for k, _, o, _ in COLLECTIONS if k == key)
            conn.execute("INSERT INTO collection_word (collection_id, word_id) VALUES (?,?)",
                         (order, cur.lastrowid))

    conn.commit()
    conn.execute("VACUUM")
    conn.close()

    # 统计各词库词数
    conn = sqlite3.connect(out_path)
    for key, name, order, _ in COLLECTIONS:
        n = conn.execute(
            "SELECT COUNT(*) FROM collection_word WHERE collection_id=?", (order,)
        ).fetchone()[0]
        print(f"  {name}({key}): {n} 词")
    conn.close()

    size_mb = out_path.stat().st_size / 1024 / 1024
    print(f"完成 -> {out_path} ({size_mb:.1f} MB)")


if __name__ == "__main__":
    main()
