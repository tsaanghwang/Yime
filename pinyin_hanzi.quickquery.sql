-- database: ./yime/pinyin_hanzi.db

SELECT name, type
FROM sqlite_master
WHERE type IN ('table', 'view')
ORDER BY type, name;
