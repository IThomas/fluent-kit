extension FluentBenchmarker {
    public func testMiddleware() throws {
        try self.testMiddleware_methods()
        try self.testMiddleware_batchCreationFail()
    }
    
    private func testMiddleware_methods() throws {
        try self.runTest(#function, [
            UserMigration(),
        ]) {

            func performTest() throws {
                let user = User(name: "A")
                // create
                do {
                    try user.create(on: self.database).wait()
                } catch let error as TestError {
                    XCTAssertEqual(error.string, "didCreate")
                }
                XCTAssertEqual(user.name, "B")

                // update
                user.name = "C"
                do {
                    try user.update(on: self.database).wait()
                } catch let error as TestError {
                    XCTAssertEqual(error.string, "didUpdate")
                }
                XCTAssertEqual(user.name, "D")

                // soft delete
                do {
                    try user.delete(force: false, on: self.database).wait()
                } catch let error as TestError {
                    XCTAssertEqual(error.string, "didDelete(force: false)")
                }
                XCTAssertEqual(user.name, "E")

                // restore
                do {
                    try user.restore(on: self.database).wait()
                } catch let error as TestError {
                    XCTAssertEqual(error.string, "didRestore")
                }
                XCTAssertEqual(user.name, "F")

                // force delete
                do {
                    try user.delete(force: true, on: self.database).wait()
                } catch let error as TestError {
                    XCTAssertEqual(error.string, "didDelete(force: true)")
                }
                XCTAssertEqual(user.name, "G")
            }

            self.databases.middleware.use(UserMiddleware())
            defer { self.databases.middleware.clear() }
            try performTest()

            self.databases.middleware.use(UserMiddlewareDeprecated())
            defer { self.databases.middleware.clear() }
            try performTest()
        }
    }
    
    private func testMiddleware_batchCreationFail() throws {
        try self.runTest(#function, [
            UserMigration(),
        ]) {
            self.databases.middleware.use(UserBatchMiddleware())
            defer { self.databases.middleware.clear() }

            let user = User(name: "A")
            let user2 = User(name: "B")
            let user3 = User(name: "C")
          
            XCTAssertThrowsError(try [user, user2, user3].create(on: self.database).wait()) { error in
                let testError = (error as? TestError)
                XCTAssertEqual(testError?.string, "cancelCreation")
            }
            
            let userCount = try User.query(on: self.database).count().wait()
            XCTAssertEqual(userCount, 0)
        }
    }
}

private struct TestError: Error {
    var string: String
}

private final class User: Model {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Timestamp(key: "deletedAt", on: .delete)
    var deletedAt: Date?

    init() { }

    init(id: IDValue? = nil, name: String) {
        self.id = id
        self.name = name
    }
}

private struct UserBatchMiddleware: ModelMiddleware {
    func create(models: [User], on db: Database, next: AnyModelResponder) -> EventLoopFuture<Void> {
        db.eventLoop.makeFailedFuture(TestError(string: "cancelCreation"))
    }
}

private struct UserMiddleware: ModelMiddleware {
    func create(models: [User], on db: Database, next: AnyModelResponder) -> EventLoopFuture<Void> {
        models[0].name = "B"
        return next.create(models, on: db).flatMap {
            return db.eventLoop.makeFailedFuture(TestError(string: "didCreate"))
        }
    }

    func update(models: [User], on db: Database, next: AnyModelResponder) -> EventLoopFuture<Void> {
        models[0].name = "D"
        return next.update(models, on: db).flatMap {
            return db.eventLoop.makeFailedFuture(TestError(string: "didUpdate"))
        }
    }

    func delete(models: [User], force: Bool, on db: Database, next: AnyModelResponder) -> EventLoopFuture<Void> {
        if force {
            models[0].name = "G"
        } else {
            models[0].name = "E"
        }
        return next.delete(models, force: force, on: db).flatMap {
            return db.eventLoop.makeFailedFuture(TestError(string: "didDelete(force: \(force))"))
        }
    }

    func restore(models: [User], on db: Database, next: AnyModelResponder) -> EventLoopFuture<Void> {
        models[0].name = "F"
        return next.restore(models , on: db).flatMap {
            return db.eventLoop.makeFailedFuture(TestError(string: "didRestore"))
        }
    }
}

@available(*, deprecated)
private struct UserMiddlewareDeprecated: ModelMiddleware {
    func create(model: User, on db: Database, next: AnyModelResponder) -> EventLoopFuture<Void> {
        model.name = "B"

        return next.create(model, on: db).flatMap {
            return db.eventLoop.makeFailedFuture(TestError(string: "didCreate"))
        }
    }

    func update(model: User, on db: Database, next: AnyModelResponder) -> EventLoopFuture<Void> {
        model.name = "D"
        return next.update(model, on: db).flatMap {
            return db.eventLoop.makeFailedFuture(TestError(string: "didUpdate"))
        }
    }

    func delete(model: User, force: Bool, on db: Database, next: AnyModelResponder) -> EventLoopFuture<Void> {
        if force {
            model.name = "G"
        } else {
            model.name = "E"
        }
        return next.delete(model, force: force, on: db).flatMap {
            return db.eventLoop.makeFailedFuture(TestError(string: "didDelete(force: \(force))"))
        }
    }

    func restore(model: User, on db: Database, next: AnyModelResponder) -> EventLoopFuture<Void> {
        model.name = "F"
        return next.restore(model , on: db).flatMap {
            return db.eventLoop.makeFailedFuture(TestError(string: "didRestore"))
        }
    }
}

private struct UserMigration: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("users")
            .field("id", .uuid, .identifier(auto: false))
            .field("name", .string, .required)
            .field("deletedAt", .datetime)
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("users").delete()
    }
}
