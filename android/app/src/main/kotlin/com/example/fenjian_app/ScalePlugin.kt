package com.example.fenjian_app

import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread
import java.nio.charset.Charset

class ScalePlugin: FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var sink: EventChannel.EventSink? = null

    // 串口对象/读线程/校准参数
    @Volatile private var running = false
    private var tareOffset = 0.0
    private var scaleFactor = 1.0 // 可做成 Map<Int,Double>；参考 Python 的 {1:11.42,...}

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods = MethodChannel(binding.binaryMessenger, "com.example.fenjian_app.scale/methods")
        methods.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "com.example.fenjian_app.scale/weight")
        events.setStreamHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    override fun onListen(args: Any?, es: EventChannel.EventSink?) { sink = es }
    override fun onCancel(args: Any?) { sink = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when(call.method) {
            "start" -> {
                val port = call.argument<String>("port") ?: "/dev/ttyS3"
                val baud = call.argument<Int>("baud") ?: 9600
                startReading(port, baud)
                result.success(null)
            }
            "stop" -> { running = false; result.success(null) }
            "tare" -> { tareOffset = 0.0; result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun startReading(portName: String, baud: Int) {
        if (running) return
        running = true
        thread(name = "scale-reader") {
            // TODO: 初始化串口（略，按厂商/usb-serial 实现）
            // val port = ...
            val regex = Regex("""([-+]?\d+(?:\.\d+)?)""") // 和 Python 类似：提取数字

            while(running) {
                try {
                    // val bytes = port.read(buffer, timeout)
                    // 示例：假设读到 ASCII 帧 "ST,GS,+0012.34 kg\r\n"
                    val frame = /* String(bytes, 0, len, Charset.forName("ASCII")) */ ""
                    val m = regex.find(frame)
                    if (m != null) {
                        val raw = m.groupValues[1].toDouble()
                        val weight = (raw * scaleFactor - tareOffset)
                        sink?.success(mapOf("id" to 1, "weight" to weight))
                    }
                } catch (t: Throwable) {
                    // 记录日志，不打断循环
                }
            }
            // port.close()
        }
    }
}
