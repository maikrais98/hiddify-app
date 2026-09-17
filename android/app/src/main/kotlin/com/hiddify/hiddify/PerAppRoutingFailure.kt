package com.hiddify.hiddify

data class PerAppRoutingFailure(
    val code: String,
    val state: String,
    val message: String,
    val canOpenSettings: Boolean = false,
) {
    fun details(): Map<String, Any> = mapOf(
        "state" to state,
        "canOpenSettings" to canOpenSettings,
    )

    companion object {
        fun from(error: Throwable): PerAppRoutingFailure = when (error) {
            is SecurityException -> PerAppRoutingFailure(
                code = "PER_APP_ROUTING_RESTRICTED",
                state = "denied",
                message = "Installed-app inventory is restricted by Android or device policy",
            )
            else -> PerAppRoutingFailure(
                code = "PER_APP_ROUTING_UNAVAILABLE",
                state = "unavailable",
                message = "Installed-app inventory is temporarily unavailable",
            )
        }
    }
}
