-- Active: 1758452649352@@127.0.0.1@3306@mysql
-- 1) 备份原表（保留数据）
CREATE TABLE IF NOT EXISTS `table_name_backup` AS SELECT * FROM `table_name`;

-- 2) （可选）为备份表建索引以提升 view 查询性能
CREATE INDEX IF NOT EXISTS idx_backup_colA ON `table_name_backup`(`colA`);
CREATE INDEX IF NOT EXISTS idx_backup_colB_colC ON `table_name_backup`(`colB`,`colC`);

-- 3) 删除或重命名原表后创建同名 view（推荐重命名以便回滚）
ALTER TABLE `table_name` RENAME TO `table_name__deprecated`; -- 可回滚
CREATE VIEW `table_name` AS SELECT * FROM `table_name_backup`;

-- 4) 通过权限控制把写权限收回，确保只读（示例：撤销普通用户写权限）
REVOKE INSERT, UPDATE, DELETE ON `your_db`.`table_name` FROM 'some_user'@'host';
-- 或只给只读账号授予 SELECT 权限
GRANT SELECT ON `your_db`.`table_name` TO 'readonly_user'@'host';

SHOW TABLES LIKE 'table_name_backup';
SHOW FULL TABLES WHERE Table_type = 'VIEW' AND Tables_in_%schema% LIKE 'table_name'; -- 替换 %schema% 为当前数据库名，或用下面两句
SHOW CREATE VIEW `table_name`;
SELECT COUNT(*) FROM `table_name` LIMIT 1;
SELECT * FROM `table_name` LIMIT 10;
