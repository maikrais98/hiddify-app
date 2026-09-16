package com.hiddify.hiddify

import java.io.File
import java.nio.file.Files
import java.util.concurrent.Callable
import java.util.concurrent.Executors

private class MemoryPersistence(initial: ByteArray? = null) : LocalControlCredentialPersistence {
    private var stored = initial

    @Synchronized
    override fun load(): ByteArray? = stored?.copyOf()

    @Synchronized
    override fun insertIfAbsent(candidate: ByteArray): ByteArray {
        val existing = stored
        if (existing != null) return existing.copyOf()
        stored = candidate.copyOf()
        return candidate.copyOf()
    }
}

private class LockedFilePersistence(directory: File) : LocalControlCredentialPersistence {
    private val data = File(directory, "credential")
    private val lock = File(directory, "credential.lock")

    override fun load(): ByteArray? = LocalControlFileLock.withLock(lock) {
        if (data.exists()) data.readBytes() else null
    }

    override fun insertIfAbsent(candidate: ByteArray): ByteArray = LocalControlFileLock.withLock(lock) {
        if (data.exists()) return@withLock data.readBytes()
        data.writeBytes(candidate)
        candidate.copyOf()
    }
}

fun main() {
    stableAcrossConcurrentOwners()
    corruptedStorageFailsClosed()
    missingExistingCredentialFailsClosed()
    println("android credential lifecycle contract: PASS")
}

private fun stableAcrossConcurrentOwners() {
    val directory = Files.createTempDirectory("wir-credential-lock").toFile()
    val persistence = LockedFilePersistence(directory)
    val counterLock = Any()
    var counter = 0
    fun store() = LocalControlCredentialStore(
        persistence = persistence,
        randomBytes = { ByteArray(it) { 0xab.toByte() } },
        generation = { synchronized(counterLock) { "generation-${++counter}" } },
    )

    try {
        val executor = Executors.newFixedThreadPool(8)
        val credentials = try {
            executor.invokeAll(List(16) { Callable { store().loadOrCreate() } }).map { it.get() }
        } finally {
            executor.shutdownNow()
        }

        check(credentials.toSet().size == 1)
        check(credentials.first().secret == "ab".repeat(32))
        check(credentials.first() == store().loadExisting())
    } finally {
        directory.deleteRecursively()
    }
}

private fun corruptedStorageFailsClosed() {
    var generated = false
    val store = LocalControlCredentialStore(
        persistence = MemoryPersistence("not-a-record".toByteArray()),
        randomBytes = {
            generated = true
            ByteArray(it)
        },
        generation = { "replacement" },
    )

    val error = runCatching { store.loadOrCreate() }.exceptionOrNull()
    check(error is LocalControlCredentialException)
    check(error.failure == LocalControlCredentialFailure.CORRUPT)
    check(!generated)
}

private fun missingExistingCredentialFailsClosed() {
    val store = LocalControlCredentialStore(
        persistence = MemoryPersistence(),
        randomBytes = { ByteArray(it) },
        generation = { "unused" },
    )

    val error = runCatching { store.loadExisting() }.exceptionOrNull()
    check(error is LocalControlCredentialException)
    check(error.failure == LocalControlCredentialFailure.MISSING)
}
