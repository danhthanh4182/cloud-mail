package dev.danhthanh.cloudmail.nativeapp

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.view.View
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

internal const val MAIL_HTML_VIEW_TYPE = "cloud_mail/html_body"

internal class MailHtmlViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        MailHtmlView(context, MethodChannel(messenger, "$MAIL_HTML_VIEW_TYPE/$viewId"))
}

private class MailHtmlView(context: Context, private val channel: MethodChannel) : PlatformView {
    private val container = FrameLayout(context)
    private var browser: WebView? = try {
        createBrowser(context)
    } catch (_: RuntimeException) {
        null // Android can have a missing or disabled WebView implementation.
    }

    init {
        browser?.let { container.addView(it, FrameLayout.LayoutParams(-1, -1)) }
        channel.setMethodCallHandler { call, result ->
            val view = browser
            when {
                call.method != "render" -> result.notImplemented()
                view == null -> result.error("unavailable", "HTML renderer is unavailable", null)
                else -> {
                    view.settings.textZoom = (call.argument<Int>("zoom") ?: 100).coerceIn(50, 250)
                    call.argument<String>("html")?.let { html ->
                        view.loadDataWithBaseURL("https://cloud-mail.invalid/", html, "text/html", "UTF-8", null)
                    }
                    result.success(null)
                }
            }
        }
    }

    private fun createBrowser(context: Context): WebView {
        val view = object : WebView(context) {
            private var reportedHeight = 0

            override fun onDraw(canvas: Canvas) {
                super.onDraw(canvas)
                // Content height is in CSS pixels. The viewport is fixed at one
                // CSS pixel per logical pixel and text zoom changes the layout.
                val current = contentHeight
                if (current > 0 && current != reportedHeight) {
                    reportedHeight = current
                    post {
                        if (browser === this && reportedHeight == current) {
                            // A sender can declare arbitrary CSS heights. Keep pathological
                            // sizes out of platform layout and use the Flutter fallback.
                            if (current > 24000) channel.invokeMethod("unavailable", null)
                            else channel.invokeMethod("height", current)
                        }
                    }
                }
            }
        }
        view.setBackgroundColor(Color.WHITE)
        view.isVerticalScrollBarEnabled = false
        view.isHorizontalScrollBarEnabled = true
        view.overScrollMode = View.OVER_SCROLL_NEVER
        with(view.settings) {
            javaScriptEnabled = false
            blockNetworkLoads = true
            allowFileAccess = false
            allowContentAccess = false
            domStorageEnabled = false
            setSupportMultipleWindows(false)
            setSupportZoom(false)
            useWideViewPort = true
            loadWithOverviewMode = false
        }
        view.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (request.isForMainFrame && request.hasGesture() && !request.isRedirect) {
                    channel.invokeMethod("link", request.url.toString())
                }
                return true
            }

            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                closeBrowser()
                channel.invokeMethod("unavailable", null)
                return true
            }
        }
        return view
    }

    private fun closeBrowser() {
        val view = browser ?: return
        browser = null
        container.removeView(view)
        view.destroy()
    }

    override fun getView(): View = container

    override fun dispose() {
        channel.setMethodCallHandler(null)
        closeBrowser()
    }
}
