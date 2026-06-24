<!DOCTYPE html>
<html>
<head>
<title>Tailscale VPN</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="-1">
<link rel="stylesheet" type="text/css" href="all.css">
<script type="text/javascript" src="jquery.js"></script>
<script type="text/javascript" src="general.js"></script>
</head>
<body onload="initial();">
<div id="wrapper">
    <div class="table_header">Cấu hình VPN Tailscale</div>
    
    <form method="post" name="form" action="/apply.cgi" target="hidden_frame">
    <input type="hidden" name="current_page" value="Advanced_Tailscale.asp">
    <input type="hidden" name="next_page" value="Advanced_Tailscale.asp">
    <input type="hidden" name="action_mode" value="Restart_Tailscale">
    <input type="hidden" name="action_script" value="">
    
    <table class="table_layout">
        <!-- Bật/Tắt dịch vụ -->
        <tr class="table_row">
            <td width="50%">Kích hoạt dịch vụ Tailscale:</td>
            <td>
                <select name="tailscale_enable" class="input">
                    <option value="0" <% nvram_match_x("", "tailscale_enable", "0", "selected"); %>>Tắt (Disable)</option>
                    <option value="1" <% nvram_match_x("", "tailscale_enable", "1", "selected"); %>>Bật (Enable)</option>
                </select>
            </td>
        </tr>
        
        <!-- Chia sẻ dải mạng LAN -->
        <tr class="table_row">
            <td>Chia sẻ dải mạng LAN (Advertise Subnets):</td>
            <td>
                <input type="text" name="tailscale_subnets" class="input" style="width: 250px;" value="<% nvram_get_x("", "tailscale_subnets"); %>" placeholder="Ví dụ: 192.168.123.0/24">
            </td>
        </tr>
        
        <!-- Bật cấu hình Exit Node -->
        <tr class="table_row">
            <td>Bật làm nút Exit Node cho mạng:</td>
            <td>
                <select name="tailscale_exitnode" class="input">
                    <option value="0" <% nvram_match_x("", "tailscale_exitnode", "0", "selected"); %>>Tắt (Disable)</option>
                    <option value="1" <% nvram_match_x("", "tailscale_exitnode", "1", "selected"); %>>Bật (Enable)</option>
                </select>
            </td>
        </tr>
        
        <!-- Chấp nhận định tuyến khác -->
        <tr class="table_row">
            <td>Nhận định tuyến của máy khác (Accept Routes):</td>
            <td>
                <select name="tailscale_accept_routes" class="input">
                    <option value="0" <% nvram_match_x("", "tailscale_accept_routes", "0", "selected"); %>>Tắt (Disable)</option>
                    <option value="1" <% nvram_match_x("", "tailscale_accept_routes", "1", "selected"); %>>Bật (Enable)</option>
                </select>
            </td>
        </tr>
        
        <!-- Sử dụng DNS từ mạng Tailscale -->
        <tr class="table_row">
            <td>Sử dụng DNS từ Tailscale (Accept DNS):</td>
            <td>
                <select name="tailscale_accept_dns" class="input">
                    <option value="0" <% nvram_match_x("", "tailscale_accept_dns", "0", "selected"); %>>Tắt (Disable)</option>
                    <option value="1" <% nvram_match_x("", "tailscale_accept_dns", "1", "selected"); %>>Bật (Enable)</option>
                </select>
            </td>
        </tr>
        
        <!-- Tham số cấu hình nâng cao -->
        <tr class="table_row">
            <td>Tham số nâng cao (Custom Arguments):</td>
            <td>
                <input type="text" name="tailscale_args" class="input" style="width: 250px;" value="<% nvram_get_x("", "tailscale_args"); %>" placeholder="Các tham số khác cho lệnh up">
            </td>
        </tr>

        <!-- Nút truy cập WebUI chính chủ -->
        <tr class="table_row">
            <td>Giao diện điều khiển WebUI:</td>
            <td>
                <script type="text/javascript">
                    var lan_ip = window.location.hostname;
                    document.write('<a href="http://' + lan_ip + ':8989" target="_blank" class="button" style="padding: 6px 16px; background-color: #0076a3; color: white; text-decoration: none; border-radius: 3px; font-weight: bold;">Mở Bảng Điều Khiển Tailscale</a>');
                </script>
            </td>
        </tr>
    </table>
    
    <!-- Nút lưu cài đặt -->
    <div class="table_footer">
        <input type="submit" name="button" class="button" value="Áp dụng cấu hình">
    </div>
    </form>
</div>
<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>
</body>
</html>
