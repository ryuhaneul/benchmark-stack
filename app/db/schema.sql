-- Database creation is now handled by server.js
-- CREATE DATABASE IF NOT EXISTS testdb;
-- USE testdb;

-- Items table for testing CRUD operations
CREATE TABLE IF NOT EXISTS items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    quantity INT DEFAULT 0,
    price DECIMAL(10, 2) DEFAULT 0.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_name (name),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Performance test results table
CREATE TABLE IF NOT EXISTS performance_tests (
    id INT AUTO_INCREMENT PRIMARY KEY,
    test_type VARCHAR(50) NOT NULL,
    iterations INT NOT NULL,
    duration_ms INT NOT NULL,
    throughput INT,
    details JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_test_type (test_type),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 초기 데이터 시딩 (이미 데이터가 있으면 스킵하거나, 필요시 TRUNCATE 후 실행)
-- 여기서는 간단히 데이터가 없을 때만 1000개 추가
INSERT INTO items (name, description, quantity, price)
SELECT 
  CONCAT('Item ', n), 
  CONCAT('Description for item ', n), 
  FLOOR(RAND() * 100), 
  ROUND(RAND() * 1000, 2)
FROM (
  SELECT a.N + b.N * 10 + c.N * 100 + 1 AS n
  FROM 
   (SELECT 0 AS N UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) a,
   (SELECT 0 AS N UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) b,
   (SELECT 0 AS N UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) c
  ORDER BY n
) t
WHERE NOT EXISTS (SELECT 1 FROM items LIMIT 1)
LIMIT 1000;

-- Insert sample data
INSERT INTO items (name, description, quantity, price) VALUES
    ('Sample Item 1', 'This is a test item', 10, 9.99),
    ('Sample Item 2', 'Another test item', 5, 19.99),
    ('Sample Item 3', 'Third test item', 15, 29.99);
