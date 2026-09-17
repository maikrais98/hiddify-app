package com.hiddify.hiddify.utils

/*
 * Copyright (C) 2019 Square, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import com.hiddify.core.mobile.Mobile
import com.hiddify.hiddify.LocalControlCredentials
import com.hiddify.hiddify.Settings
import com.squareup.wire.GrpcClient
import okhttp3.OkHttpClient
import java.io.ByteArrayInputStream
import java.security.KeyStore
import java.security.cert.CertificateFactory
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

object GrpcClientProvider {
    // Build from the active native session, never from system trust or a TCP peer.
    val grpcClient: GrpcClient
        get() {
            val certificate = CertificateFactory.getInstance("X.509")
                .generateCertificate(ByteArrayInputStream(Mobile.getServerPublicKey()))
            val store = KeyStore.getInstance(KeyStore.getDefaultType()).apply {
                load(null, null)
                setCertificateEntry("local-control", certificate)
            }
            val trust = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply { init(store) }
            val manager = trust.trustManagers.single() as X509TrustManager
            val context = SSLContext.getInstance("TLS").apply { init(null, arrayOf(manager), null) }
            val secret = LocalControlCredentials.store.loadExisting().secret
            val client = OkHttpClient.Builder()
                .sslSocketFactory(context.socketFactory, manager)
                .addInterceptor { chain -> chain.proceed(chain.request().newBuilder()
                    .header("authorization", "Bearer $secret").build()) }
                .connectTimeout(10, TimeUnit.SECONDS)
                .readTimeout(10, TimeUnit.SECONDS)
                .writeTimeout(10, TimeUnit.SECONDS)
                .build()
            return GrpcClient.Builder().client(client)
                .baseUrl("https://127.0.0.1:${Settings.grpcServiceModePort}").build()
        }
}
