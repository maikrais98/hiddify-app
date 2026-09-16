package com.hiddify.hiddify

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.io.FileOutputStream
import java.security.GeneralSecurityException
import java.security.KeyStore
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class EncryptedLocalControlCredentialPersistence(context: Context) : LocalControlCredentialPersistence {
    private val directory = context.noBackupFilesDir
    private val credentialFile = File(directory, "local-control-credential.v1")
    private val lockFile = File(directory, "local-control-credential.lock")

    override fun load(): ByteArray? = withFileLock {
        if (!credentialFile.exists()) return@withFileLock null
        decrypt(credentialFile.readBytes())
    }

    override fun insertIfAbsent(candidate: ByteArray): ByteArray = withFileLock {
        if (credentialFile.exists()) return@withFileLock decrypt(credentialFile.readBytes())
        directory.mkdirs()
        val temporary = File(directory, "local-control-credential.tmp")
        try {
            FileOutputStream(temporary).use { output ->
                output.write(encrypt(candidate))
                output.fd.sync()
            }
            if (!temporary.renameTo(credentialFile)) {
                throw LocalControlCredentialException(LocalControlCredentialFailure.UNAVAILABLE)
            }
            credentialFile.setReadable(false, false)
            credentialFile.setWritable(false, false)
            credentialFile.setReadable(true, true)
            credentialFile.setWritable(true, true)
            candidate.copyOf()
        } finally {
            if (temporary.exists()) temporary.delete()
        }
    }

    private fun encrypt(plaintext: ByteArray): ByteArray = protect {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key(createIfMissing = true))
        cipher.updateAAD(AAD)
        MAGIC + byteArrayOf(cipher.iv.size.toByte()) + cipher.iv + cipher.doFinal(plaintext)
    }

    private fun decrypt(envelope: ByteArray): ByteArray {
        if (envelope.size < MAGIC.size + 1 + IV_SIZE + TAG_SIZE ||
            !envelope.copyOfRange(0, MAGIC.size).contentEquals(MAGIC)
        ) {
            throw LocalControlCredentialException(LocalControlCredentialFailure.CORRUPT)
        }
        val ivSize = envelope[MAGIC.size].toInt() and 0xff
        if (ivSize != IV_SIZE || envelope.size <= MAGIC.size + 1 + ivSize) {
            throw LocalControlCredentialException(LocalControlCredentialFailure.CORRUPT)
        }
        val ivStart = MAGIC.size + 1
        return try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                key(createIfMissing = false),
                GCMParameterSpec(TAG_SIZE * 8, envelope.copyOfRange(ivStart, ivStart + ivSize)),
            )
            cipher.updateAAD(AAD)
            cipher.doFinal(envelope.copyOfRange(ivStart + ivSize, envelope.size))
        } catch (error: AEADBadTagException) {
            throw LocalControlCredentialException(LocalControlCredentialFailure.CORRUPT, error)
        } catch (error: LocalControlCredentialException) {
            throw error
        } catch (error: GeneralSecurityException) {
            throw LocalControlCredentialException(LocalControlCredentialFailure.UNAVAILABLE, error)
        }
    }

    private fun key(createIfMissing: Boolean): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        if (!createIfMissing) {
            throw LocalControlCredentialException(LocalControlCredentialFailure.UNAVAILABLE)
        }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun <T> withFileLock(action: () -> T): T {
        return try {
            directory.mkdirs()
            LocalControlFileLock.withLock(lockFile, action)
        } catch (error: LocalControlCredentialException) {
            throw error
        } catch (error: Exception) {
            throw LocalControlCredentialException(LocalControlCredentialFailure.UNAVAILABLE, error)
        }
    }

    private fun <T> protect(action: () -> T): T = try {
        action()
    } catch (error: LocalControlCredentialException) {
        throw error
    } catch (error: GeneralSecurityException) {
        throw LocalControlCredentialException(LocalControlCredentialFailure.UNAVAILABLE, error)
    }

    companion object {
        private const val KEY_ALIAS = "woman_in_red.local_control.v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_SIZE = 12
        private const val TAG_SIZE = 16
        private val MAGIC = byteArrayOf(0x57, 0x49, 0x52, 0x01)
        private val AAD = "woman-in-red/local-control/v1".toByteArray(Charsets.UTF_8)
    }
}
