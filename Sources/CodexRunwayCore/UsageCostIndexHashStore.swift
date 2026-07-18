import Foundation

extension UsageCostIndexStore {
    func sourceHashCacheRows() throws -> [UsageCostCachedFullHash] {
        let sql = """
            SELECT device, inode, birth_ns, size, mtime_ns, ctime_ns, full_hash
            FROM source_hash_cache
            """
        return try database.withStatement(sql, operation: "read source hash cache") { statement in
            var rows: [UsageCostCachedFullHash] = []
            while try statement.step() {
                if rows.count.isMultiple(of: 512) { try Task.checkCancellation() }
                rows.append(try decodeUsageCostCachedFullHash(statement))
            }
            return rows
        }
    }

    func replaceSourceHashCache(with rows: [UsageCostCachedFullHash]) throws {
        try database.transaction {
            try database.execute("DELETE FROM source_hash_cache", operation: "clear source hash cache")
            let statement = try database.prepare(
                """
                INSERT INTO source_hash_cache(
                    device, inode, birth_ns, size, mtime_ns, ctime_ns, full_hash)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                operation: "prepare source hash insert")
            for row in rows.sorted(by: Self.hashCacheOrder) {
                try Task.checkCancellation()
                try statement.bind(row.identity.device, at: 1)
                try statement.bind(row.identity.inode, at: 2)
                try statement.bind(row.identity.birthTimeNanoseconds, at: 3)
                try statement.bind(sqliteInteger(row.size, field: "cached hash size"), at: 4)
                try statement.bind(row.modificationTimeNanoseconds, at: 5)
                try statement.bind(row.statusChangeTimeNanoseconds, at: 6)
                try statement.bind(row.digest, at: 7)
                _ = try statement.step()
                try statement.reset()
            }
        }
    }

    private static func hashCacheOrder(
        _ lhs: UsageCostCachedFullHash,
        _ rhs: UsageCostCachedFullHash
    ) -> Bool {
        let left = lhs.identity
        let right = rhs.identity
        if left.device != right.device { return left.device < right.device }
        if left.inode != right.inode { return left.inode < right.inode }
        return left.birthTimeNanoseconds < right.birthTimeNanoseconds
    }
}
