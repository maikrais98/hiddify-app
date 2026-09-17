package com.hiddify.hiddify

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class PerAppRoutingFailureTest {
    @Test
    fun `security exception is restricted without a settings recovery`() {
        val failure = PerAppRoutingFailure.from(SecurityException("blocked by policy"))

        assertEquals("PER_APP_ROUTING_RESTRICTED", failure.code)
        assertEquals("denied", failure.state)
        assertFalse(failure.canOpenSettings)
    }

    @Test
    fun `unexpected inventory error is unavailable without a settings recovery`() {
        val failure = PerAppRoutingFailure.from(IllegalStateException("package manager unavailable"))

        assertEquals("PER_APP_ROUTING_UNAVAILABLE", failure.code)
        assertEquals("unavailable", failure.state)
        assertFalse(failure.canOpenSettings)
    }
}
