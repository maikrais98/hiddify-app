package com.hiddify.hiddify

object LocalControlCredentials {
    val store: LocalControlCredentialStore by lazy {
        LocalControlCredentialStore(
            EncryptedLocalControlCredentialPersistence(Application.application.applicationContext),
        )
    }
}
