package com.example.fenjian_app

import android.app.PendingIntent
import android.content.*
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.Charset
import java.util.concurrent.Executors
import java.util.concurrent.ExecutorService
import java.util.concurrent.atomic.AtomicBoolean
import android.util.Log
import com.hoho.android.usbserial.driver.UsbSerialDriver
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import com.hoho.android.usbserial.util.SerialInputOutputManager

object ScaleBridge :
    EventChannel.StreamHandler,
    MethodChannel.MethodCallHandler,
    SerialInputOutputManager.Listener {

    private const val METHOD_CHANNEL = "com.example.fenjian_app.scale/methods"
    private const val EVENT_CHANNEL  = "com.example.fenjian_app.scale/weight"
    private const val TAG = "ScaleBridge"
    private const val ACTION_USB_PERMISSION = "com.example.fenjian_app.USB_PERMISSION"

    private var appContext: Context? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    @Volatile private var eventSink: EventChannel.EventSink? = null

    private var driver: UsbSerialDriver? = null
    private var port: UsbSerialPort? = null
    private var ioManager: SerialInputOutputManager? = null
    private var ioExecutor: ExecutorService? = null
    private var permissionReceiver: BroadcastReceiver? = null

    private val running = AtomicBoolean(false)
    private var tare1: Long? = null
    private var tare2: Long? = null
    private var factor1: Double = 11.420884
    private var factor2: Double = 11.807084
    private var dir1: Int = +1
    private var dir2: Int = -1
    private var lastAsciiEmitMs = 0L
    private val asciiNumberRegex = Regex("""([-+]?\d+(?:\.\d+)?)""")

    private val mainHandler by lazy { android.os.Handler(android.os.Looper.getMainLooper()) }

    // FF + 3字节值 + 55 的 6字节帧（12个hex字符）
    private val hexBuf = StringBuilder()

    fun setup(context: Context, engine: FlutterEngine) {
        if (methodChannel != null && eventChannel != null) return

        appContext = context.applicationContext
        val messenger = engine.dartExecutor.binaryMessenger

        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(messenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    // ========= EventChannel.StreamHandler =========
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // ========= MethodChannel.MethodCallHandler =========
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "list" -> {
                result.success(listUsbDevices())
            }
            "start" -> {
                val baud = call.argument<Int>("baud") ?: 9600
                val vid  = call.argument<Int>("vid")
                val pid  = call.argument<Int>("pid")
                val devName = call.argument<String>("deviceName")
                factor1 = call.argument<Double>("factor1") ?: factor1
                factor2 = call.argument<Double>("factor2") ?: factor2
                dir1    = call.argument<Int>("dir1") ?: dir1
                dir2    = call.argument<Int>("dir2") ?: dir2
                startSerial(baud, vid, pid, devName)
                result.success(null)
            }
            "stop" -> {
                stopSerial()
                result.success(null)
            }
            "tare" -> {
                val id = call.argument<Int>("id") // 可能是 null / 1 / 2
                when (id) {
                    1 -> tare1 = null
                    2 -> tare2 = null
                    else -> { tare1 = null; tare2 = null } // 全部
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun listUsbDevices(): List<Map<String, Any>> {
        val ctx = appContext ?: return emptyList()
        val usb = ctx.getSystemService(Context.USB_SERVICE) as UsbManager
        return usb.deviceList.values.map { d: UsbDevice ->
            mapOf(
                "vendorId" to d.vendorId,
                "productId" to d.productId,
                "deviceName" to d.deviceName
            )
        }
    }

    private fun startSerial(baud: Int, vid: Int?, pid: Int?, deviceName: String?) {
        if (!running.compareAndSet(false, true)) return

        val ctx = appContext ?: run {
            Log.e(TAG, "startSerial: appContext is null")
            running.set(false)
            return
        }
        val usb = ctx.getSystemService(Context.USB_SERVICE) as UsbManager
        val available = usb.deviceList.values.toList()

        val target: UsbDevice? = when {
            !deviceName.isNullOrBlank() -> available.firstOrNull { it.deviceName == deviceName }
            vid != null && pid != null  -> available.firstOrNull { it.vendorId == vid && it.productId == pid }
            else                        -> available.firstOrNull()
        }

        if (target == null) {
            Log.w(TAG, "No matching USB device found")
            running.set(false)
            return
        }

        val drv = UsbSerialProber.getDefaultProber().probeDevice(target)
        if (drv == null) {
            Log.w(TAG, "UsbSerialProber returned null for ${target.deviceName}")
            running.set(false)
            return
        }
        driver = drv

        if (!usb.hasPermission(target)) {
            val filter = IntentFilter(ACTION_USB_PERMISSION)
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(c: Context, intent: Intent) {
                    if (intent.action == ACTION_USB_PERMISSION) {
                        val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                        try {
                            if (granted) openAndRead(usb, baud)
                            else {
                                Log.e(TAG, "User denied USB permission for ${target.deviceName}")
                                running.set(false)
                            }
                        } finally {
                            try { c.unregisterReceiver(this) } catch (_: Throwable) {}
                            permissionReceiver = null
                        }
                    }
                }
            }
            permissionReceiver = receiver
            ctx.registerReceiver(receiver, filter)

            val pi = PendingIntent.getBroadcast(
                ctx, 0,
                Intent(ACTION_USB_PERMISSION),
                PendingIntent.FLAG_IMMUTABLE
            )
            usb.requestPermission(target, pi)
        } else {
            openAndRead(usb, baud)
        }
    }

    private fun openAndRead(usb: UsbManager, baud: Int) {
        val drv = driver ?: run {
            Log.e(TAG, "openAndRead: driver is null")
            running.set(false)
            return
        }

        val conn = usb.openDevice(drv.device)
        if (conn == null) {
            Log.e(TAG, "usb.openDevice failed for ${drv.device.deviceName}")
            running.set(false)
            return
        }

        val p = drv.ports.firstOrNull()
        if (p == null) {
            Log.e(TAG, "No ports for driver ${drv.device.deviceName}")
            running.set(false)
            return
        }
        port = p

        try {
            Log.d(TAG, "openAndRead: ports=${drv.ports.size}, using first")
            p.open(conn)
            p.setParameters(baud, 8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE)

            // ★★★ 关键：HXN 常见需要这三步，否则一直 0 字节
            try {
                p.setDTR(true)
                p.setRTS(true)
                p.purgeHwBuffers(true, true)
                Log.d(TAG, "openAndRead: setParameters ok @ $baud 8N1, DTR/RTS raised & buffers purged")
            } catch (e: Throwable) {
                Log.w(TAG, "set control lines/purge failed: ${e.message}")
            }

            // （可选）轻微 DTR 脉冲，有些设备需要这个“唤醒”
            try {
                Thread.sleep(30)
                p.setDTR(false)
                Thread.sleep(30)
                p.setDTR(true)
            } catch (_: Throwable) { }

            // ★ 加一轮“打招呼”
            wakeDevice(p)

            startManualReader(p)
        } catch (e: Throwable) {
            Log.e(TAG, "openAndRead failed", e)
            running.set(false)
            try { p.close() } catch (_: Throwable) {}
            port = null
        }
    }
    private fun wakeDevice(p: UsbSerialPort) {
        try {
            // 常见秤命令：换行 / 询问 / 去皮 / 查询；不认识会被忽略，一般安全
            val seqs = arrayOf("\r\n", "?\r\n", "Q\r\n", "W\r\n")
            for (s in seqs) {
                val b = s.toByteArray(Charset.forName("US-ASCII"))
                p.write(b, 100)
                Thread.sleep(20)
            }
            Log.d(TAG, "wakeDevice: probe bytes sent")
        } catch (e: Throwable) {
            Log.w(TAG, "wakeDevice failed: ${e.message}")
        }
    }

    private fun startManualReader(p: UsbSerialPort) {
        ioExecutor = Executors.newSingleThreadExecutor()
        ioExecutor?.submit {
            val buf = ByteArray(4096)
            var lastLogMs = 0L
            var lastDataMs = System.currentTimeMillis()

            while (running.get()) {
                try {
                    val n = p.read(buf, 1000) // 1s 超时
                    val now = System.currentTimeMillis()

                    if (n > 0) {
                        onNewBytes(buf, n)
                        lastDataMs = now
                    } else {
                        if (now - lastLogMs > 1000) {
                            Log.d(TAG, "still waiting data...")
                            lastLogMs = now
                        }
                        // ★ 3 秒没数据，尝试再唤醒一次
                        if (now - lastDataMs > 3000) {
                            wakeDevice(p)
                            lastDataMs = now
                        }
                    }
                } catch (e: Exception) {
                    if (running.get()) Log.w(TAG, "read loop error: ${e.message}")
                    break
                }
            }

            Log.d(TAG, "Manual reader thread end")
        }
    }


    // 手动读线程调用：只处理有效长度 n
    private fun onNewBytes(data: ByteArray, n: Int) {
        if (!running.get()) return

        // 先累积到 HEX 缓冲，确保能跨包拼帧
        for (i in 0 until n) hexBuf.append(String.format("%02x", data[i]))

        // 备份 ASCII 文本（仅当真的像样时才解析）
        val ascii = try { String(data, 0, n, Charset.forName("ASCII")) } catch (_: Throwable) { "" }

        var parsedAny = false

        // 1) 解析固定 6 字节帧：ff + id(1B) + val(3B) + 55
        var idx = hexBuf.indexOf("ff")
        while (idx >= 0) {
            if (hexBuf.length - idx < 12) break
            val candidate = hexBuf.substring(idx, idx + 12)
            if (candidate.endsWith("55")) {
                try {
                    val idHex  = candidate.substring(2, 4)
                    val valHex = candidate.substring(4, 10)
                    val scaleId  = Integer.parseInt(idHex, 16)
                    val nowValue = java.lang.Long.parseLong(valHex, 16)

                    when (scaleId) {
                        1 -> {
                            if (tare1 == null) tare1 = nowValue
                            val rawDiff = (nowValue - (tare1 ?: 0)) * dir1
                            val weight  = (rawDiff / factor1) / 1000.0
                            emitWeight(1, weight)
                            parsedAny = true
                        }
                        2 -> {
                            if (tare2 == null) tare2 = nowValue
                            val rawDiff = (nowValue - (tare2 ?: 0)) * dir2
                            val weight  = (rawDiff / factor2) / 1000.0
                            emitWeight(2, weight)
                            parsedAny = true
                        }
                        else -> {
                            // 未知ID，忽略
                        }
                    }
                } catch (_: Throwable) {
                    // 单帧解析失败不阻塞后续
                }
                // 丢弃本帧
                hexBuf.delete(idx, idx + 12)
                idx = hexBuf.indexOf("ff")
            } else {
                // 非有效帧头，跳过两个字符继续找
                hexBuf.delete(idx, idx + 2)
                idx = hexBuf.indexOf("ff")
            }
        }

        // 2) ASCII 路径（谨慎）：避免把二进制错当数字
        if (!parsedAny && ascii.isNotEmpty() && looksLikeAsciiStableLine(ascii)) {
            val now = System.currentTimeMillis()
            if (now - lastAsciiEmitMs > 100) {
                val m = asciiNumberRegex.find(ascii)
                val num = m?.groupValues?.getOrNull(1)?.toDoubleOrNull()
                if (num != null) {
                    emitWeight(1, num) // 如需区分秤号，可在这里解析ASCII行中的通道信息
                    lastAsciiEmitMs = now
                }
            }
        }
    }

    // 判断这段 ASCII 是否“像样”：可打印比例高且包含常见秤关键字
    private fun looksLikeAsciiStableLine(s: String): Boolean {
        val printable = s.count { it in ' '..'~' }
        val ratio = if (s.isNotEmpty()) printable.toDouble() / s.length else 0.0
        return ratio > 0.9 && (s.contains("kg", true) || s.contains("ST,", true) || s.contains("GS,", true))
    }

    private fun emitWeight(id: Int, weight: Double) {
        val sink = eventSink ?: return
        mainHandler.post {
            try {
                sink.success(mapOf("id" to id, "weight" to weight))
            } catch (_: Throwable) {
                // ignore
            }
        }
    }

    private fun stopSerial() {
        running.set(false)
        try { ioManager?.stop() } catch (_: Throwable) {}
        ioManager = null
        try { ioExecutor?.shutdownNow() } catch (_: Throwable) {}
        ioExecutor = null
        try { port?.close() } catch (_: Throwable) {}
        port = null
        driver = null
        val ctx = appContext
        if (ctx != null && permissionReceiver != null) {
            try { ctx.unregisterReceiver(permissionReceiver) } catch (_: Throwable) {}
            permissionReceiver = null
        }
        hexBuf.setLength(0)
        tare1 = null
        tare2 = null
    }

    // ========= 必须实现的接口方法（即使不用也要有） =========
    override fun onNewData(data: ByteArray) {
        // 我们使用手动读取 + onNewBytes 来解析，这里留空避免双重解析
        // 如果未来改回使用 SerialInputOutputManager，可把解析挪到这里
    }

    override fun onRunError(e: Exception) {
        Log.w(TAG, "Serial IO run error: ${e.message}")
    }
}
