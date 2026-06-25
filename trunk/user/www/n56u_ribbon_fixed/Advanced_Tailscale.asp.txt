<!DOCTYPE html>
<html>
<head>
<title><#Web_Title#> - Tailscale VPN</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="-1">
<link rel="shortcut icon" href="images/favicon.ico">
<link rel="icon" href="images/favicon.png">
<link rel="stylesheet" type="text/css" href="/bootstrap/css/bootstrap.min.css">
<link rel="stylesheet" type="text/css" href="/bootstrap/css/main.css">
<link rel="stylesheet" type="text/css" href="/bootstrap/css/engage.itoggle.css">
<script type="text/javascript" src="/jquery.js"></script>
<script type="text/javascript" src="/bootstrap/js/bootstrap.min.js"></script>
<script type="text/javascript" src="/bootstrap/js/engage.itoggle.min.js"></script>
<script type="text/javascript" src="/state.js"></script>
<script type="text/javascript" src="/general.js"></script>
<script type="text/javascript" src="/itoggle.js"></script>
<script type="text/javascript" src="/popup.js"></script>
<script type="text/javascript" src="/help.js"></script>
<script type="text/javascript" src="/help_b.js"></script>
<script>
var $j = jQuery.noConflict();
$j(document).ready(function() {
	init_itoggle('ts_enable',      change_ts_enabled);
	init_itoggle('ts_exitnode',    null);
	init_itoggle('ts_accept_routes', null);
	init_itoggle('ts_allow_lan',   null);
	init_itoggle('ts_shields_up',  null);
	change_ts_enabled();
	refresh_status();
});
</script>
<script>
<% login_state_hook(); %>

function initial(){
	show_banner(2);
	show_menu(5,22);
	show_footer();
}

function change_ts_enabled(){
	var el0 = document.getElementById('ts_enable_0');
	var disabled = el0 ? el0.checked : false;
	showhide_div('ts_settings', disabled ? 0 : 1);
}

function refresh_status(){
	$j.ajax({
		url: '/status_tailscale.asp',
		type: 'GET',
		timeout: 5000,
		success: function(data) {
			var ip   = (data.match(/ts_ip=([^\n]+)/)   || ['','--'])[1].trim();
			var stat = (data.match(/ts_status=([^\n]+)/) || ['','Unknown'])[1].trim();
			var ver  = (data.match(/ts_version=([^\n]+)/) || ['','--'])[1].trim();
			$j('#ts_ip_val').text(ip);
			$j('#ts_status_val').text(stat);
			$j('#ts_ver_val').text(ver);
			var cls = stat.indexOf('running') >= 0 ? 'label-success' : 'label-danger';
			$j('#ts_status_badge').removeClass('label-success label-danger label-warning').addClass(cls);
		},
		error: function() {
			$j('#ts_status_val').text('Error fetching status');
		}
	});
	setTimeout(refresh_status, 10000);
}

function do_download(){
	if(!confirm('Download Tailscale binary from GitHub? Cần kết nối Internet.')) return;
	showLoading();
	$j.ajax({
		url: '/start_apply.htm',
		type: 'POST',
		data: { action_script: 'download_tailscale', action_mode: ' Apply ' },
		complete: function(){
			hideLoading();
			alert('Download started. Kiểm tra log để theo dõi tiến trình.');
		}
	});
}

function do_update(){
	if(!confirm('Update Tailscale lên phiên bản mới nhất?')) return;
	showLoading();
	document.form.action_script.value = 'update_tailscale';
	document.form.action_mode.value = ' Apply ';
	document.form.submit();
}

function open_admin(){
	window.open('https://login.tailscale.com/admin', '_blank');
}

function applyRule(){
	showLoading();
	document.form.action_mode.value = ' Apply ';
	document.form.current_page.value = '/Advanced_Tailscale.asp';
	document.form.next_page.value = '';
	document.form.action_script.value = 'restart_tailscale';
	document.form.submit();
}
</script>
</head>

<body onload="initial();" onunLoad="return unload_body();">
<div class="wrapper">
<div class="container-fluid" style="padding-right:0px">
	<div class="row-fluid">
		<div class="span3"><center><div id="logo"></div></center></div>
		<div class="span9"><div id="TopBanner"></div></div>
	</div>
</div>

<div id="Loading" class="popup_bg"></div>
<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>

<form method="post" name="form" id="ruleForm" action="/start_apply.htm" target="hidden_frame">
<input type="hidden" name="current_page"  value="Advanced_Tailscale.asp">
<input type="hidden" name="next_page"     value="">
<input type="hidden" name="next_host"     value="">
<input type="hidden" name="sid_list"      value="TailscaleConf;">
<input type="hidden" name="group_id"      value="">
<input type="hidden" name="action_mode"   value="">
<input type="hidden" name="action_script" value="restart_tailscale">

<div class="container-fluid">
<div class="row-fluid">
	<div class="span3">
		<div class="well sidebar-nav side_nav" style="padding:0px;">
			<ul id="mainMenu" class="clearfix"></ul>
			<ul class="clearfix"><li><div id="subMenu" class="accordion"></div></li></ul>
		</div>
	</div>

	<div class="span9">
	<div class="row-fluid"><div class="span12">
	<div class="box well grad_colour_dark_blue">
		<h2 class="box_head round_top">Tailscale VPN</h2>
		<div class="round_bottom">
		<div class="row-fluid">
		<div id="tabMenu" class="submenuBlock"></div>

		<!-- Status Panel -->
		<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">
			<tr>
				<th width="30%" style="border-top:0 none;">Status</th>
				<td style="border-top:0 none;">
					<span id="ts_status_badge" class="label label-warning">
						<span id="ts_status_val">Loading...</span>
					</span>
					&nbsp;
					<button type="button" class="btn btn-mini btn-info"
						onclick="open_admin()">
						🌐 Open Tailscale Admin
					</button>
				</td>
			</tr>
			<tr>
				<th>Tailscale IP</th>
				<td><strong><span id="ts_ip_val">--</span></strong></td>
			</tr>
			<tr>
				<th>Version</th>
				<td>
					<span id="ts_ver_val">--</span>
					&nbsp;
					<button type="button" class="btn btn-mini btn-warning"
						onclick="do_update()">⬆ Update</button>
					&nbsp;
					<button type="button" class="btn btn-mini btn-default"
						onclick="do_download()">⬇ Download Binary</button>
				</td>
			</tr>
		</table>

		<hr style="margin:5px 0"/>

		<!-- Enable Toggle -->
		<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">
			<tr>
				<th width="30%">Enable Tailscale</th>
				<td>
					<div class="main_itoggle">
						<div id="ts_enable_on_of">
							<input type="checkbox" id="ts_enable_fake"
								<% nvram_match_x("","ts_enable","1","value=1 checked"); %>
								<% nvram_match_x("","ts_enable","0","value=0"); %> />
						</div>
					</div>
					<div style="position:absolute;margin-left:-10000px;">
						<input type="radio" value="1" name="ts_enable" id="ts_enable_1"
							<% nvram_match_x("","ts_enable","1","checked"); %>
							onclick="change_ts_enabled();" />&nbsp;Yes
						<input type="radio" value="0" name="ts_enable" id="ts_enable_0"
							<% nvram_match_x("","ts_enable","0","checked"); %>
							onclick="change_ts_enabled();" />&nbsp;No
					</div>
				</td>
			</tr>
		</table>

		<div id="ts_settings">
		<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">

			<!-- Auth Key -->
			<tr>
				<th width="30%">Auth Key
					<br/><span style="color:#888;font-size:11px;font-weight:normal;">
						Lấy tại tailscale.com/admin/settings/keys<br/>
						Tự xóa sau khi login thành công
					</span>
				</th>
				<td>
					<input type="password" maxlength="200" class="input" size="40"
						name="ts_authkey"
						value="<% nvram_get_x("","ts_authkey"); %>"
						placeholder="tskey-auth-xxxx..." />
				</td>
			</tr>

			<!-- Hostname -->
			<tr>
				<th>Hostname
					<br/><span style="color:#888;font-size:11px;font-weight:normal;">Để trống = dùng tên router</span>
				</th>
				<td>
					<input type="text" maxlength="63" class="input" size="30"
						name="ts_hostname"
						value="<% nvram_get_x("","ts_hostname"); %>"
						placeholder="my-router" />
				</td>
			</tr>

			<!-- Exit Node -->
			<tr>
				<th>Advertise Exit Node
					<br/><span style="color:#888;font-size:11px;font-weight:normal;">
						Router làm exit node cho toàn bộ traffic
					</span>
				</th>
				<td>
					<div class="main_itoggle">
						<div id="ts_exitnode_on_of">
							<input type="checkbox" id="ts_exitnode_fake"
								<% nvram_match_x("","ts_exitnode","1","value=1 checked"); %>
								<% nvram_match_x("","ts_exitnode","0","value=0"); %> />
						</div>
					</div>
					<div style="position:absolute;margin-left:-10000px;">
						<input type="radio" value="1" name="ts_exitnode" id="ts_exitnode_1"
							<% nvram_match_x("","ts_exitnode","1","checked"); %> />Yes
						<input type="radio" value="0" name="ts_exitnode" id="ts_exitnode_0"
							<% nvram_match_x("","ts_exitnode","0","checked"); %> />No
					</div>
				</td>
			</tr>

			<!-- Allow LAN -->
			<tr>
				<th>Allow LAN Access
					<br/><span style="color:#888;font-size:11px;font-weight:normal;">
						Cho phép truy cập LAN khi dùng exit node
					</span>
				</th>
				<td>
					<div class="main_itoggle">
						<div id="ts_allow_lan_on_of">
							<input type="checkbox" id="ts_allow_lan_fake"
								<% nvram_match_x("","ts_allow_lan","1","value=1 checked"); %>
								<% nvram_match_x("","ts_allow_lan","0","value=0"); %> />
						</div>
					</div>
					<div style="position:absolute;margin-left:-10000px;">
						<input type="radio" value="1" name="ts_allow_lan" id="ts_allow_lan_1"
							<% nvram_match_x("","ts_allow_lan","1","checked"); %> />Yes
						<input type="radio" value="0" name="ts_allow_lan" id="ts_allow_lan_0"
							<% nvram_match_x("","ts_allow_lan","0","checked"); %> />No
					</div>
				</td>
			</tr>

			<!-- Subnet -->
			<tr>
				<th>Advertise Subnet
					<br/><span style="color:#888;font-size:11px;font-weight:normal;">
						Chia sẻ subnet LAN qua Tailscale
					</span>
				</th>
				<td>
					<input type="text" maxlength="50" class="input" size="25"
						name="ts_subnet"
						value="<% nvram_get_x("","ts_subnet"); %>"
						placeholder="192.168.123.0/24" />
				</td>
			</tr>

			<!-- Accept Routes -->
			<tr>
				<th>Accept Routes
					<br/><span style="color:#888;font-size:11px;font-weight:normal;">
						Nhận routes từ các node khác
					</span>
				</th>
				<td>
					<div class="main_itoggle">
						<div id="ts_accept_routes_on_of">
							<input type="checkbox" id="ts_accept_routes_fake"
								<% nvram_match_x("","ts_accept_routes","1","value=1 checked"); %>
								<% nvram_match_x("","ts_accept_routes","0","value=0"); %> />
						</div>
					</div>
					<div style="position:absolute;margin-left:-10000px;">
						<input type="radio" value="1" name="ts_accept_routes" id="ts_accept_routes_1"
							<% nvram_match_x("","ts_accept_routes","1","checked"); %> />Yes
						<input type="radio" value="0" name="ts_accept_routes" id="ts_accept_routes_0"
							<% nvram_match_x("","ts_accept_routes","0","checked"); %> />No
					</div>
				</td>
			</tr>

			<!-- Shields Up -->
			<tr>
				<th>Shields Up
					<br/><span style="color:#888;font-size:11px;font-weight:normal;">
						Chặn mọi kết nối đến từ Tailscale
					</span>
				</th>
				<td>
					<div class="main_itoggle">
						<div id="ts_shields_up_on_of">
							<input type="checkbox" id="ts_shields_up_fake"
								<% nvram_match_x("","ts_shields_up","1","value=1 checked"); %>
								<% nvram_match_x("","ts_shields_up","0","value=0"); %> />
						</div>
					</div>
					<div style="position:absolute;margin-left:-10000px;">
						<input type="radio" value="1" name="ts_shields_up" id="ts_shields_up_1"
							<% nvram_match_x("","ts_shields_up","1","checked"); %> />Yes
						<input type="radio" value="0" name="ts_shields_up" id="ts_shields_up_0"
							<% nvram_match_x("","ts_shields_up","0","checked"); %> />No
					</div>
				</td>
			</tr>

		</table>
		</div><!-- ts_settings -->

		<!-- Apply Button -->
		<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">
			<tr>
				<td colspan="2" style="border-top:0 none;">
					<br/>
					<center>
						<input class="btn btn-primary" style="width:219px" type="button"
							value="<#CTL_apply#>" onclick="applyRule()" />
					</center>
				</td>
			</tr>
		</table>

		</div></div>
	</div>
	</div></div>
	</div>
</div>
</div>
</form>

<div id="footer"></div>
</div>
</body>
</html>
