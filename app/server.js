const express = require('express');
const bodyParser = require('body-parser');
const mysql = require('mysql2/promise');
const { Worker } = require('worker_threads');
const path = require('path');

const app = express();
const PORT = process.env.APP_PORT || 3000;

// Middleware
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// 정적 파일 서빙 (웹 UI)
app.use(express.static(path.join(__dirname, 'public')));

// Database connection pool configuration
const dbConfig = {
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT) || 3306,
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || 'password',
  database: process.env.DB_NAME || 'testdb',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
  enableKeepAlive: true,
  keepAliveInitialDelay: 0
};

// Create connection pool
let pool;

const fs = require('fs');

async function initializeDatabase() {
  try {
    pool = mysql.createPool(dbConfig);
    console.log('✅ Database connection pool created');

    // Test connection
    const connection = await pool.getConnection();
    console.log('✅ Database connection test successful');

    // Execute Schema Script
    try {
      const schemaPath = path.join(__dirname, 'db', 'schema.sql');
      const schemaSql = fs.readFileSync(schemaPath, 'utf8');
      const statements = schemaSql.split(';').filter(stmt => stmt.trim().length > 0);

      for (const statement of statements) {
        await connection.query(statement);
      }
      console.log('✅ Database schema initialized and seeded');
    } catch (err) {
      console.error('⚠️ Failed to initialize schema:', err.message);
    } finally {
      connection.release();
    }

  } catch (error) {
    console.error('❌ Database connection failed:', error.message);
    process.exit(1);
  }
}

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'Test API Server (Performance Mode)',
    endpoints: {
      health: 'GET /health',
      performance: {
        cpu: 'GET /api/performance/cpu',
        cpuMulti: 'GET /api/performance/cpu-multi',
        dbRead: 'GET /api/performance/db-read',
        dbWrite: 'POST /api/performance/db-write',
        history: 'GET /api/performance/history',
        deleteOne: 'DELETE /api/performance/:id',
        deleteAll: 'DELETE /api/performance'
      }
    }
  });
});

// ===== Performance Test Endpoints =====

// CPU 벤치마크 테스트
app.get('/api/performance/cpu', async (req, res) => {
  const iterations = parseInt(req.query.iterations) || 100000000;
  const startTime = Date.now();

  // CPU 집약적 작업: 소수 찾기
  let primes = [];
  for (let i = 2; primes.length < iterations / 100; i++) {
    let isPrime = true;
    for (let j = 2; j <= Math.sqrt(i); j++) {
      if (i % j === 0) {
        isPrime = false;
        break;
      }
    }
    if (isPrime) primes.push(i);
  }

  const endTime = Date.now();
  const duration = endTime - startTime;
  const throughput = Math.round(primes.length / (duration / 1000));

  const result = {
    success: true,
    test: 'CPU Benchmark',
    iterations: iterations,
    primesFound: primes.length,
    duration: duration,
    durationSeconds: (duration / 1000).toFixed(3),
    throughput: throughput
  };

  // DB에 결과 저장 (skip_save 파라미터가 없을 때만)
  if (req.query.skip_save !== 'true') {
    try {
      await pool.query(
        'INSERT INTO performance_tests (test_type, iterations, duration_ms, throughput, details) VALUES (?, ?, ?, ?, ?)',
        ['CPU', iterations, duration, throughput, JSON.stringify({ primesFound: primes.length })]
      );
    } catch (error) {
      console.error('Failed to save CPU test result:', error);
    }
  }

  res.json(result);
});

// 데이터베이스 읽기 성능 테스트
app.get('/api/performance/db-read', async (req, res) => {
  const iterations = parseInt(req.query.iterations) || 50000;
  const threads = parseInt(req.query.threads) || 1; // Default to 1 (single thread) if not specified
  const startTime = Date.now();

  try {
    let totalRows = 0;

    if (threads > 1) {
      // Multi-threaded execution
      const iterationsPerThread = Math.floor(iterations / threads);
      const workerPromises = [];

      for (let i = 0; i < threads; i++) {
        workerPromises.push(new Promise((resolve, reject) => {
          const worker = new Worker(path.join(__dirname, 'worker.js'), {
            workerData: {
              taskType: 'DB_READ',
              iterations: iterationsPerThread,
              dbConfig: dbConfig
            }
          });

          worker.on('message', resolve);
          worker.on('error', reject);
          worker.on('exit', (code) => {
            if (code !== 0) reject(new Error(`Worker stopped with exit code ${code}`));
          });
        }));
      }

      const results = await Promise.all(workerPromises);
      totalRows = results.reduce((a, b) => a + b, 0);

    } else {
      // Single-threaded execution (Main Event Loop)
      for (let i = 0; i < iterations; i++) {
        const [rows] = await pool.query('SELECT * FROM items');
        totalRows += rows.length;
      }
    }

    const endTime = Date.now();
    const duration = endTime - startTime;
    const throughput = Math.round(iterations / (duration / 1000));
    const avgQueryTime = (duration / iterations).toFixed(2);

    const result = {
      success: true,
      test: 'Database Read',
      iterations: iterations,
      threads: threads,
      totalRowsRead: totalRows,
      duration: duration,
      durationSeconds: (duration / 1000).toFixed(3),
      throughput: throughput,
      avgQueryTime: avgQueryTime
    };

    // DB에 결과 저장 (skip_save 파라미터가 없을 때만)
    if (req.query.skip_save !== 'true') {
      try {
        await pool.query(
          'INSERT INTO performance_tests (test_type, iterations, duration_ms, throughput, details) VALUES (?, ?, ?, ?, ?)',
          ['DB_READ', iterations, duration, throughput, JSON.stringify({ threads, totalRowsRead: totalRows, avgQueryTime: avgQueryTime })]
        );
      } catch (error) {
        console.error('Failed to save DB read test result:', error);
      }
    }

    res.json(result);
  } catch (error) {
    console.error('DB Read test error:', error);
    res.status(500).json({
      success: false,
      error: 'Database read test failed',
      message: error.message
    });
  }
});

// 데이터베이스 쓰기 성능 테스트
app.post('/api/performance/db-write', async (req, res) => {
  const iterations = parseInt(req.body.iterations) || 5000;
  const threads = parseInt(req.body.threads) || 1;
  const startTime = Date.now();

  try {
    let insertedIds = [];

    if (threads > 1) {
      // Multi-threaded execution
      const iterationsPerThread = Math.floor(iterations / threads);
      const workerPromises = [];

      for (let i = 0; i < threads; i++) {
        workerPromises.push(new Promise((resolve, reject) => {
          const worker = new Worker(path.join(__dirname, 'worker.js'), {
            workerData: {
              taskType: 'DB_WRITE',
              iterations: iterationsPerThread,
              dbConfig: dbConfig
            }
          });

          worker.on('message', resolve);
          worker.on('error', reject);
          worker.on('exit', (code) => {
            if (code !== 0) reject(new Error(`Worker stopped with exit code ${code}`));
          });
        }));
      }

      const results = await Promise.all(workerPromises);
      // Flatten results (arrays of IDs)
      insertedIds = results.flat();

    } else {
      // Single-threaded execution
      for (let i = 0; i < iterations; i++) {
        const [result] = await pool.query(
          'INSERT INTO items (name, description, quantity, price) VALUES (?, ?, ?, ?)',
          [`Perf Test ${i}`, `Performance test item ${i}`, Math.floor(Math.random() * 100), Math.random() * 100]
        );
        insertedIds.push(result.insertId);
      }
    }

    // 테스트 데이터 정리
    if (insertedIds.length > 0) {
      // Chunk delete to avoid query size limits if too many items
      const chunkSize = 1000;
      for (let i = 0; i < insertedIds.length; i += chunkSize) {
        const chunk = insertedIds.slice(i, i + chunkSize);
        await pool.query('DELETE FROM items WHERE id IN (?)', [chunk]);
      }
    }

    const endTime = Date.now();
    const duration = endTime - startTime;
    const throughput = Math.round(iterations / (duration / 1000));
    const avgQueryTime = (duration / iterations).toFixed(2);

    const result = {
      success: true,
      test: 'Database Write',
      iterations: iterations,
      threads: threads,
      rowsInserted: insertedIds.length,
      duration: duration,
      durationSeconds: (duration / 1000).toFixed(3),
      throughput: throughput,
      avgQueryTime: avgQueryTime
    };

    // DB에 결과 저장 (skip_save 파라미터가 없을 때만)
    if (req.query.skip_save !== 'true') {
      try {
        await pool.query(
          'INSERT INTO performance_tests (test_type, iterations, duration_ms, throughput, details) VALUES (?, ?, ?, ?, ?)',
          ['DB_WRITE', iterations, duration, throughput, JSON.stringify({ threads, rowsInserted: insertedIds.length, avgQueryTime: avgQueryTime })]
        );
      } catch (error) {
        console.error('Failed to save DB write test result:', error);
      }
    }

    res.json(result);
  } catch (error) {
    console.error('DB Write test error:', error);
    res.status(500).json({
      success: false,
      error: 'Database write test failed',
      message: error.message
    });
  }
});

// CPU 다중 스레드 벤치마크 (Worker Threads 사용)
app.get('/api/performance/cpu-multi', async (req, res) => {
  const iterations = parseInt(req.query.iterations) || 100000000;
  const threads = parseInt(req.query.threads) || 4;
  const startTime = Date.now();

  const iterationsPerThread = Math.floor(iterations / threads);
  const workers = [];

  try {
    // 워커 생성 및 실행
    const workerPromises = [];
    for (let i = 0; i < threads; i++) {
      workerPromises.push(new Promise((resolve, reject) => {
        const worker = new Worker(path.join(__dirname, 'worker.js'), {
          workerData: {
            taskType: 'CPU',
            iterations: iterationsPerThread
          }
        });

        worker.on('message', resolve);
        worker.on('error', reject);
        worker.on('exit', (code) => {
          if (code !== 0) reject(new Error(`Worker stopped with exit code ${code}`));
        });
      }));
    }
    // 모든 워커 완료 대기
    const results = await Promise.all(workerPromises);
    const totalPrimes = results.reduce((a, b) => a + b, 0);

    const endTime = Date.now();
    const duration = endTime - startTime;

    // 결과 저장 (skip_save 파라미터가 없을 때만)
    if (req.query.skip_save !== 'true') {
      const [result] = await pool.query(
        'INSERT INTO performance_tests (test_type, iterations, duration_ms, throughput, details) VALUES (?, ?, ?, ?, ?)',
        ['CPU_MULTI', iterations, duration, Math.round(iterations / (duration / 1000)), JSON.stringify({ threads, primesFound: totalPrimes })]
      );
    }

    res.json({
      success: true,
      test_type: 'CPU_MULTI',
      duration: duration,
      durationSeconds: duration / 1000,
      iterations: iterations,
      threads: threads,
      primesFound: totalPrimes,
      throughput: Math.round(iterations / (duration / 1000)),
      message: `Multi-thread CPU test completed in ${duration}ms using ${threads} threads`
    });

  } catch (error) {
    console.error('Multi-thread CPU test failed:', error);
    res.status(500).json({
      success: false,
      error: 'Test failed',
      message: error.message
    });
  }
});

// 외부(클라이언트)에서 계산된 성능 테스트 결과 저장
app.post('/api/performance/result', async (req, res) => {
  try {
    const { test_type, iterations, duration_ms, throughput, details } = req.body;

    const [result] = await pool.query(
      'INSERT INTO performance_tests (test_type, iterations, duration_ms, throughput, details) VALUES (?, ?, ?, ?, ?)',
      [test_type, iterations, duration_ms, throughput, JSON.stringify(details || {})]
    );

    res.json({
      success: true,
      message: 'Test result saved',
      id: result.insertId
    });
  } catch (error) {
    console.error('Failed to save external test result:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to save test result',
      message: error.message
    });
  }
});

// 성능 테스트 내역 조회
app.get('/api/performance/history', async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 50;
    const [rows] = await pool.query(
      'SELECT * FROM performance_tests ORDER BY created_at DESC LIMIT ?',
      [limit]
    );

    res.json({
      success: true,
      count: rows.length,
      data: rows
    });
  } catch (error) {
    console.error('Failed to fetch performance history:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch performance history',
      message: error.message
    });
  }
});

// 성능 테스트 결과 개별 삭제
app.delete('/api/performance/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const [result] = await pool.query('DELETE FROM performance_tests WHERE id = ?', [id]);

    if (result.affectedRows === 0) {
      return res.status(404).json({
        success: false,
        error: 'Test result not found'
      });
    }

    res.json({
      success: true,
      message: 'Test result deleted'
    });
  } catch (error) {
    console.error('Failed to delete test result:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete test result',
      message: error.message
    });
  }
});

// 성능 테스트 전체 삭제
app.delete('/api/performance', async (req, res) => {
  try {
    const [result] = await pool.query('DELETE FROM performance_tests');

    res.json({
      success: true,
      message: 'All test results deleted',
      deletedCount: result.affectedRows
    });
  } catch (error) {
    console.error('Failed to delete all test results:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete all test results',
      message: error.message
    });
  }
});

// (Item endpoints removed)

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    success: false,
    error: 'Internal server error',
    message: err.message
  });
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM signal received: closing HTTP server');
  if (pool) {
    await pool.end();
    console.log('Database pool closed');
  }
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('SIGINT signal received: closing HTTP server');
  if (pool) {
    await pool.end();
    console.log('Database pool closed');
  }
  process.exit(0);
});

// Start server
async function startServer() {
  await initializeDatabase();

  const server = app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server running on http://0.0.0.0:${PORT}`);
    console.log(`📊 Environment: ${process.env.NODE_ENV || 'development'}`);
    console.log(`🗄️  Database: ${dbConfig.host}:${dbConfig.port}/${dbConfig.database}`);
  });

  // Set timeout to 5 minutes (300000 ms) for long-running tests
  server.setTimeout(300000);
}

startServer().catch(error => {
  console.error('Failed to start server:', error);
  process.exit(1);
});
