-- Active: 1758452649352@@127.0.0.1@3306@information_schema
-- 在 mysql 提示符或作为 .sql 文件执行（替换 AppPass 和 your_db）
CREATE USER IF NOT EXISTS 'appuser'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY 'AppPass';
GRANT SELECT, INSERT, UPDATE, DELETE ON `your_db`.* TO 'appuser'@'127.0.0.1';
FLUSH PRIVILEGES;
