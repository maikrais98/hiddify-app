package com.hiddify.hiddify

import java.io.File
import java.io.RandomAccessFile
import java.security.SecureRandom
import java.util.UUID

data class LocalControlCredential(
    val generation: String,
    val secret: String,
) {
    override fun toString(): String = "LocalControlCredential(generation=$generation, secret=<redacted>)"
}

enum class LocalControlCredentialFailure {
    MISSING,
    CORRUPT,
    UNAVAILABLE,
}

class LocalControlCredentialException(
    val failure: LocalControlCredentialFailure,
    cause: Throwable? = null,
) : Exception("Protected control credential is unavailable", cause)

interface LocalControlCredentialPersistence {
    fun load(): ByteArray?
    fun insertIfAbsent(candidate: ByteArray): ByteArray
}

object LocalControlFileLock {
    private val processMonitor = Any()

    fun <T> withLock(lockFile: File, action: () -> T): T = synchronized(processMonitor) {
        lockFile.parentFile?.mkdirs()
        RandomAccessFile(lockFile, "rw").channel.use { channel ->
            channel.lock().use { action() }
        }
    }
}

class LocalControlCredentialStore(
    private val persistence: LocalControlCredentialPersistence,
    private val randomBytes: (Int) -> ByteArray = ::secureRandomBytes,
    private val generation: () -> String = { UUID.randomUUID().toString() },
) {
    fun loadExisting(): LocalControlCredential {
        val stored = persistence.load()
            ?: throw LocalControlCredentialException(LocalControlCredentialFailure.MISSING)
        return decode(stored)
    }

    fun loadOrCreate(): LocalControlCredential {
        persistence.load()?.let { return decode(it) }
        val credential = LocalControlCredential(
            generation = generation(),
            secret = randomBytes(32).joinToString("") { "%02x".format(it.toInt() and 0xff) },
        )
        if (!credential.isValid()) {
            throw LocalControlCredentialException(LocalControlCredentialFailure.UNAVAILABLE)
        }
        return decode(persistence.insertIfAbsent(encode(credential)))
    }

    private fun encode(credential: LocalControlCredential): ByteArray =
        "1\n${credential.generation}\n${credential.secret}".toByteArray(Charsets.UTF_8)

    private fun decode(stored: ByteArray): LocalControlCredential {
        val parts = stored.toString(Charsets.UTF_8).split('\n')
        if (parts.size != 3 || parts[0] != "1") {
            throw LocalControlCredentialException(LocalControlCredentialFailure.CORRUPT)
        }
        val credential = LocalControlCredential(generation = parts[1], secret = parts[2])
        if (!credential.isValid()) {
            throw LocalControlCredentialException(LocalControlCredentialFailure.CORRUPT)
        }
        return credential
    }

    private fun LocalControlCredential.isValid(): Boolean =
        generation.isNotEmpty() &&
            generation.length <= 128 &&
            '\n' !in generation &&
            secret.length == 64 &&
            secret.all { it in '0'..'9' || it in 'a'..'f' }

    companion object {
        private val secureRandom = SecureRandom()

        private fun secureRandomBytes(count: Int) = ByteArray(count).also(secureRandom::nextBytes)
    }
}
