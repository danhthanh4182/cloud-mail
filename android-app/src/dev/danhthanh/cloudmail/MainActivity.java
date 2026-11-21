package dev.danhthanh.cloudmail;

import android.app.*;
import android.os.Bundle;
import android.content.*;
import android.net.Uri;
import android.graphics.Color;
import android.view.*;
import android.webkit.*;
import android.widget.*;

public final class MainActivity extends Activity {
    private LinearLayout root;
    private WebView web;
    private ProgressBar progress;
    private String origin = "";
    private ValueCallback<Uri[]> files;
    private static final int PICK_FILE = 41;
    private final int blue = Color.rgb(37,99,235);

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        root = new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE); setContentView(root);
        root.setOnApplyWindowInsetsListener((v,i) -> {
            v.setPadding(i.getSystemWindowInsetLeft(),i.getSystemWindowInsetTop(),i.getSystemWindowInsetRight(),i.getSystemWindowInsetBottom());
            return i.consumeSystemWindowInsets();
        });
        String saved = getPreferences(MODE_PRIVATE).getString("server", "");
        if (saved.isEmpty()) setup(); else open(saved);
    }
    private int dp(int n) { return (int)(n*getResources().getDisplayMetrics().density); }
    private Button button(String label) {
        Button b = new Button(this); b.setText(label); b.setTextColor(blue); b.setAllCaps(false); return b;
    }
    private void disposeWeb() {
        if (web != null) { web.stopLoading(); web.destroy(); web = null; }
        if (files != null) { files.onReceiveValue(null); files = null; }
        root.removeAllViews();
    }
    private void setup() {
        disposeWeb();
        LinearLayout form = new LinearLayout(this); form.setOrientation(LinearLayout.VERTICAL); form.setPadding(dp(24),dp(40),dp(24),dp(24));
        root.addView(form,new LinearLayout.LayoutParams(-1,-1));
        TextView title = new TextView(this); title.setText("Cloud Mail"); title.setTextSize(32); title.setTextColor(blue); form.addView(title);
        TextView desc = new TextView(this); desc.setText("Kết nối hộp thư của bạn\n\nNhập địa chỉ HTTPS nơi bạn đã triển khai Cloud Mail. Ứng dụng sử dụng tài khoản và giao diện webmail hiện tại."); desc.setTextSize(16); desc.setPadding(0,dp(16),0,dp(24)); form.addView(desc);
        EditText input = new EditText(this); input.setSingleLine(true); input.setHint("https://mail.tenmiencuaban.com"); input.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_VARIATION_URI);
        input.setText(getPreferences(MODE_PRIVATE).getString("server", "")); form.addView(input,new LinearLayout.LayoutParams(-1,-2));
        Button connect = button("Kết nối hộp thư"); form.addView(connect);
        connect.setOnClickListener(v -> {
            try {
                Uri uri = Uri.parse(input.getText().toString().trim());
                if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost()==null || uri.getHost().isEmpty() || uri.getUserInfo()!=null || uri.getQuery()!=null || uri.getFragment()!=null) throw new IllegalArgumentException();
                String url = uri.toString(); getPreferences(MODE_PRIVATE).edit().putString("server",url).apply(); open(url);
            } catch (Exception e) { input.setError("Nhập địa chỉ HTTPS hợp lệ, không chứa tài khoản hoặc token."); }
        });
        TextView note = new TextView(this); note.setText("Bản thử nghiệm 0.1.0 · Android 8 trở lên\nChỉ kết nối máy chủ bạn tin cậy. Chưa có thông báo đẩy khi đóng ứng dụng."); note.setPadding(0,dp(24),0,0); form.addView(note);
    }
    private boolean sameOrigin(Uri uri) {
        Uri base = Uri.parse(origin);
        return "https".equalsIgnoreCase(uri.getScheme()) && base.getHost().equalsIgnoreCase(uri.getHost()==null?"":uri.getHost()) && base.getPort()==uri.getPort();
    }
    private void external(Uri uri) {
        String scheme = uri.getScheme();
        if (!"https".equalsIgnoreCase(scheme) && !"http".equalsIgnoreCase(scheme) && !"mailto".equalsIgnoreCase(scheme) && !"tel".equalsIgnoreCase(scheme)) return;
        try { startActivity(new Intent(Intent.ACTION_VIEW,uri).addCategory(Intent.CATEGORY_BROWSABLE)); }
        catch (ActivityNotFoundException e) { Toast.makeText(this,"Không có ứng dụng mở liên kết này",Toast.LENGTH_SHORT).show(); }
    }
    private void open(String url) {
        disposeWeb(); origin = url;
        LinearLayout toolbar = new LinearLayout(this);
        TextView title = new TextView(this); title.setText("Cloud Mail"); title.setTextSize(20); title.setTextColor(blue); title.setGravity(Gravity.CENTER_VERTICAL); title.setPadding(dp(16),0,0,0);
        toolbar.addView(title,new LinearLayout.LayoutParams(0,dp(52),1));
        Button refresh = button("↻"); refresh.setContentDescription("Tải lại hộp thư"); refresh.setOnClickListener(v -> web.reload()); toolbar.addView(refresh,new LinearLayout.LayoutParams(dp(56),dp(52)));
        Button menu = button("⋮"); menu.setContentDescription("Cài đặt"); toolbar.addView(menu,new LinearLayout.LayoutParams(dp(48),dp(52))); menu.setOnClickListener(v -> options(menu)); root.addView(toolbar);
        progress = new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal); root.addView(progress,new LinearLayout.LayoutParams(-1,dp(3)));
        web = new WebView(this); root.addView(web,new LinearLayout.LayoutParams(-1,0,1));
        WebSettings s = web.getSettings(); s.setJavaScriptEnabled(true); s.setDomStorageEnabled(true); s.setAllowFileAccess(false); s.setAllowContentAccess(false); s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW); s.setSupportMultipleWindows(true);
        CookieManager.getInstance().setAcceptCookie(true); CookieManager.getInstance().setAcceptThirdPartyCookies(web,false);
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView w,WebResourceRequest r) {
                if (!r.isForMainFrame()) return false;
                if (sameOrigin(r.getUrl())) return false; external(r.getUrl()); return true;
            }
            @Override public void onPageFinished(WebView w,String u) { CookieManager.getInstance().flush(); }
            @Override public void onReceivedError(WebView w,WebResourceRequest r,WebResourceError e) {
                if (r.isForMainFrame()) new AlertDialog.Builder(MainActivity.this).setTitle("Không kết nối được hộp thư").setMessage("Kiểm tra mạng và địa chỉ máy chủ. " + e.getDescription()).setPositiveButton("Thử lại",(d,n)->w.reload()).setNegativeButton("Đổi máy chủ",(d,n)->setup()).show();
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override public void onProgressChanged(WebView w,int p) { progress.setProgress(p); progress.setVisibility(p==100?View.GONE:View.VISIBLE); }
            @Override public boolean onShowFileChooser(WebView w,ValueCallback<Uri[]> callback,FileChooserParams p) {
                if (files!=null) files.onReceiveValue(null); files=callback;
                try { startActivityForResult(p.createIntent(),PICK_FILE); } catch (ActivityNotFoundException e) { files.onReceiveValue(null); files=null; }
                return true;
            }
            @Override public boolean onCreateWindow(WebView w,boolean dialog,boolean gesture,android.os.Message msg) {
                if (!gesture) return false;
                WebView popup = new WebView(MainActivity.this);
                popup.setWebViewClient(new WebViewClient() {
                    @Override public boolean shouldOverrideUrlLoading(WebView w,WebResourceRequest r) { external(r.getUrl()); w.destroy(); return true; }
                });
                ((WebView.WebViewTransport)msg.obj).setWebView(popup); msg.sendToTarget(); return true;
            }
        });
        web.setDownloadListener((u,ua,cd,mime,length)-> {
            if (u.startsWith("https://")) {
                Toast.makeText(this,"Mở trình duyệt để tải tệp; có thể cần đăng nhập lại.",Toast.LENGTH_LONG).show(); external(Uri.parse(u));
            } else Toast.makeText(this,"Tệp này cần tải từ webmail trong trình duyệt.",Toast.LENGTH_LONG).show();
        });
        web.loadUrl(url);
    }
    private void options(View anchor) {
        PopupMenu menu = new PopupMenu(this,anchor);
        menu.getMenu().add("Mở trong trình duyệt").setOnMenuItemClickListener(i->{ external(Uri.parse(origin)); return true; });
        menu.getMenu().add("Đổi máy chủ").setOnMenuItemClickListener(i->{ setup(); return true; });
        menu.getMenu().add("Xóa phiên đăng nhập").setOnMenuItemClickListener(i->{
            new AlertDialog.Builder(this).setMessage("Xóa dữ liệu đăng nhập đã lưu trên thiết bị?").setPositiveButton("Xóa",(d,n)->{
                disposeWeb(); WebStorage.getInstance().deleteAllData(); CookieManager.getInstance().removeAllCookies(ok -> runOnUiThread(()->{ CookieManager.getInstance().flush(); setup(); }));
            }).setNegativeButton("Hủy",null).show(); return true;
        }); menu.show();
    }
    @Override protected void onActivityResult(int request,int result,Intent data) {
        super.onActivityResult(request,result,data);
        if (request==PICK_FILE && files!=null) { files.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(result,data)); files=null; }
    }
    @Override public void onBackPressed() { if (web!=null && web.canGoBack()) web.goBack(); else super.onBackPressed(); }
    @Override protected void onPause() { super.onPause(); if(web!=null) web.onPause(); CookieManager.getInstance().flush(); }
    @Override protected void onResume() { super.onResume(); if(web!=null) web.onResume(); }
    @Override protected void onDestroy() { disposeWeb(); super.onDestroy(); }
}
