const { parentPort, workerData } = require('worker_threads');
const mysql = require('mysql2/promise');

// CPU 집약적 작업: 소수 찾기
function findPrimes(iterations) {
    let primes = [];
    const targetCount = Math.floor(iterations / 100);

    for (let i = 2; primes.length < targetCount; i++) {
        let isPrime = true;
        const sqrt = Math.sqrt(i);
        for (let j = 2; j <= sqrt; j++) {
            if (i % j === 0) {
                isPrime = false;
                break;
            }
        }
        if (isPrime) primes.push(i);
    }
    return primes.length;
}

async function runDBRead(iterations, dbConfig) {
    const connection = await mysql.createConnection(dbConfig);
    let totalRows = 0;
    try {
        for (let i = 0; i < iterations; i++) {
            // 데이터 양에 상관없이 일정한 성능 측정을 위해 LIMIT 100 적용
            const [rows] = await connection.query('SELECT * FROM items LIMIT 100');
            totalRows += rows.length;
        }
    } finally {
        await connection.end();
    }
    return totalRows;
}

async function runDBWrite(iterations, dbConfig) {
    const connection = await mysql.createConnection(dbConfig);
    let insertedIds = [];
    try {
        for (let i = 0; i < iterations; i++) {
            const [result] = await connection.query(
                'INSERT INTO items (name, description, quantity, price) VALUES (?, ?, ?, ?)',
                [`Perf Test Worker`, `Worker item`, Math.floor(Math.random() * 100), Math.random() * 100]
            );
            insertedIds.push(result.insertId);
        }
    } finally {
        await connection.end();
    }
    return insertedIds;
}

async function run() {
    const { taskType, iterations, dbConfig } = workerData;

    try {
        if (taskType === 'DB_READ') {
            const result = await runDBRead(iterations, dbConfig);
            parentPort.postMessage(result);
        } else if (taskType === 'DB_WRITE') {
            const result = await runDBWrite(iterations, dbConfig);
            parentPort.postMessage(result);
        } else {
            // Default to CPU test for backward compatibility or explicit 'CPU' type
            const result = findPrimes(iterations);
            parentPort.postMessage(result);
        }
    } catch (error) {
        // Worker error handling is done by the parent listening to 'error' event,
        // but throwing here ensures it propagates.
        throw error;
    }
}

run();
