SHOW VARIABLES LIKE 'default_authentication%';
SELECT @@global.default_authentication_plugin;
SELECT User, Host, plugin FROM mysql.user WHERE User='root';

CREATE USER IF NOT EXISTS 'appuser'@'127.0.0.1' IDENTIFIED BY 'AppPass';
GRANT SELECT, INSERT, UPDATE, DELETE ON `your_db`.* TO 'appuser'@'127.0.0.1';
FLUSH PRIVILEGES;

SHOW VARIABLES LIKE 'default_authentication%';
SELECT @@global.default_authentication_plugin;
SHOW PLUGINS;
-- 推荐（兼容）：使用服务器默认认证方式
CREATE USER IF NOT EXISTS 'appuser'@'127.0.0.1' IDENTIFIED BY 'AppPass';
CREATE USER IF NOT EXISTS 'appuser'@'localhost' IDENTIFIED BY 'AppPass';
GRANT SELECT, INSERT, UPDATE, DELETE ON `your_db`.* TO 'appuser'@'127.0.0.1';
GRANT SELECT, INSERT, UPDATE, DELETE ON `your_db`.* TO 'appuser'@'localhost';
FLUSH PRIVILEGES;

CREATE DATABASE IF NOT EXISTS `your_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON `your_db`.* TO 'appuser'@'127.0.0.1';
GRANT ALL PRIVILEGES ON `your_db`.* TO 'appuser'@'localhost';
FLUSH PRIVILEGES;

# 复制到临时文件并运行，或在 REPL 中执行
import os, pymysql
conn = pymysql.connect(host='127.0.0.1', user='root', password='YourRootPass', port=3306)
cur = conn.cursor()
cur.execute("CREATE DATABASE IF NOT EXISTS `your_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;")
cur.execute("GRANT ALL PRIVILEGES ON `your_db`.* TO 'appuser'@'127.0.0.1';")
cur.execute("GRANT ALL PRIVILEGES ON `your_db`.* TO 'appuser'@'localhost';")
cur.execute("FLUSH PRIVILEGES;")
conn.commit()
conn.close()
print('done')
