package dev.gitpilot.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkflowInputsTest {
    @Test fun parsesMultipleValuesAndKeepsEqualsInsideValues() {
        val inputs = parseWorkflowInputs("environment=staging\nversion=1.2.0\nurl=https://host/?x=1")
        assertEquals("staging", inputs["environment"])
        assertEquals("1.2.0", inputs["version"])
        assertEquals("https://host/?x=1", inputs["url"])
    }

    @Test fun blankInputsAreAllowed() {
        assertTrue(parseWorkflowInputs(" \n  ").isEmpty())
    }

    @Test fun rejectsMalformedAndDuplicateInputs() {
        assertTrue(runCatching { parseWorkflowInputs("environment") }.isFailure)
        assertTrue(runCatching { parseWorkflowInputs("environment=prod\nenvironment=dev") }.isFailure)
        assertTrue(runCatching { parseWorkflowInputs("invalid input=value") }.isFailure)
    }

    @Test fun rejectsMoreThanTenInputs() {
        val text = (1..11).joinToString("\n") { "key" + it + "=value" }
        assertTrue(runCatching { parseWorkflowInputs(text) }.isFailure)
    }
}
