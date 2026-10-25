package com.brainbuddy.app.core

import android.os.Handler
import android.os.Looper
import java.util.concurrent.CopyOnWriteArraySet

/** Tells the open app screen that counts changed, so it can refresh live. */
object CountBus {
    private val listeners = CopyOnWriteArraySet<() -> Unit>()
    private val main = Handler(Looper.getMainLooper())

    fun listen(l: () -> Unit) { listeners.add(l) }
    fun remove(l: () -> Unit) { listeners.remove(l) }
    fun emit() = main.post { listeners.forEach { it() } }
}
