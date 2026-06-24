<!DOCTYPE html>
<html>
<head>
<title><#Web_Title#> - SQM QoS</title>
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
	init_itoggle('sqm_enable', change_sqm_enabled);
	change_sqm_enabled();
	change_preset();
});
</script>
<script>
<% login_state_hook(); %>

var PRESET_DESC = {
	"none":      "Không ưu tiên. Chỉ shaping bandwidth cơ bản.",
	"gaming":    "ECN + DSCP EF cho game UDP (Liên Quân, PUBG, DOTA2...). Bulk download xuống thấp.",
	"streaming": "Ưu tiên HTTPS/UDP 443 cho Netflix, YouTube, Twitch. Bulk xuống thấp.",
	"wfh":       "Ưu tiên Zoom, Meet, Teams (EF). Web browsing (AF31). Bulk xuống thấp.",
	"balanced":  "ECN bật. Chỉ hạ thấp bulk khi connection > 10MB. Phù hợp dùng chung.",
	"custom":    "Tự nhập UDP port range ưu tiên cao nhất (EF)."
};

function initial(){
	show_banner(2);
	show_menu(5,21);
	show_footer();
	build_dynamic_sqm_interfaces();
}

function change_sqm_enabled(){
	var el0 = document.getElementById('sqm_enable_0');
	var disabled = el0 ? el0.checked : false;
	showhide_div('sqm_settings', disabled ? 0 : 1);
}

function change_preset(){
	var sel = document.getElementById('sqm_preset_select');
	var preset = sel ? sel.value : 'none';

	// Hiện/ẩn custom ports row
	showhide_div('custom_ports_row', preset === 'custom' ? 1 : 0);

	// Cập nhật mô tả
	var desc = PRESET_DESC[preset] || '';
	var el = document.getElementById('preset_desc');
	if (el) el.innerHTML = desc;
}

function build_dynamic_sqm_interfaces() {
	var active_wan   = '<% nvram_get_x("", "wan0_ifname_t"); %>';
	var active_phy   = '<% nvram_get_x("", "wan0_phy_ifname_t"); %>';
	var active_apcli = '<% nvram_get_x("", "apcli_ifname"); %>';
	var saved_val    = '<% nvram_get_x("", "sqm_iface"); %>';

	var interfaces = [];
	if (active_wan   && active_wan   !== '') interfaces.push(active_wan);
	if (active_phy   && active_phy   !== '' && interfaces.indexOf(active_phy)   === -1) interfaces.push(active_phy);
	if (active_apcli && active_apcli !== '' && interfaces.indexOf(active_apcli) === -1) interfaces.push(active_apcli);
	if (interfaces.length === 0) interfaces = ['eth3','ppp0','apclii0','apcli0'];
	if (saved_val && saved_val !== '' && interfaces.indexOf(saved_val) === -1) interfaces.push(saved_val);

	var sel = document.getElementById('sqm_iface_select');
	sel.options.length = 0;
	for (var i = 0; i < interfaces.length; i++) {
		var iface = interfaces[i];
		var label = iface;
		if (iface === 'eth3')    label += ' (WAN có dây)';
		else if (iface === 'ppp0')    label += ' (PPPoE)';
		else if (iface === 'apclii0') label += ' (Kích sóng 5G)';
		else if (iface === 'apcli0')  label += ' (Kích sóng 2.4G)';
		var opt = document.createElement('option');
		opt.value = iface; opt.text = label;
		if (iface === saved_val) opt.selected = true;
		sel.add(opt);
	}
}

function applyRule(){
	showLoading();
	document.form.action_mode.value = ' Apply ';
	document.form.current_page.value = '/Advanced_SQM_Content.asp';
	document.form.next_page.value = '';
	document.form.action_script.value = 'restart_sqm';
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
<input type="hidden" name="current_page"  value="Advanced_SQM_Content.asp">
<input type="hidden" name="next_page"     value="">
<input type="hidden" name="next_host"     value="">
<input type="hidden" name="sid_list"      value="SQMConf;">
<input type="hidden" name="group_id"      value="">
<input type="hidden" name="action_mode"   value="">
<input type="hidden" name="action_script" value="restart_sqm">

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
		<h2 class="box_head round_top">SQM QoS</h2>
		<div class="round_bottom">
		<div class="row-fluid">
		<div id="tabMenu" class="submenuBlock"></div>

		<!-- Enable toggle -->
		<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">
			<tr>
				<th width="30%" style="border-top:0 none;">Enable SQM</th>
				<td style="border-top:0 none;">
					<div class="main_itoggle">
						<div id="sqm_enable_on_of">
							<input type="checkbox" id="sqm_enable_fake"
								<% nvram_match_x("","sqm_enable","1","value=1 checked"); %>
								<% nvram_match_x("","sqm_enable","0","value=0"); %> />
						</div>
					</div>
					<div style="position:absolute;margin-left:-10000px;">
						<input type="radio" value="1" name="sqm_enable" id="sqm_enable_1" class="input"
							<% nvram_match_x("","sqm_enable","1","checked"); %>
							onclick="change_sqm_enabled();" /><#checkbox_Yes#>
						<input type="radio" value="0" name="sqm_enable" id="sqm_enable_0" class="input"
							<% nvram_match_x("","sqm_enable","0","checked"); %>
							onclick="change_sqm_enabled();" /><#checkbox_No#>
					</div>
				</td>
			</tr>
		</table>

		<div id="sqm_settings">
		<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">

			<!-- Interface -->
			<tr>
				<th width="30%">WAN Interface</th>
				<td>
					<select class="input" name="sqm_iface" id="sqm_iface_select" style="width:219px;"></select>
				</td>
			</tr>

			<!-- Bandwidth -->
			<tr>
				<th>Download Bandwidth (kbps)</th>
				<td>
					<input type="text" maxlength="10" class="input" size="15" name="sqm_down"
						value="<% nvram_get_x("","sqm_down"); %>" placeholder="e.g. 90000" />
				</td>
			</tr>
			<tr>
				<th>Upload Bandwidth (kbps)</th>
				<td>
					<input type="text" maxlength="10" class="input" size="15" name="sqm_up"
						value="<% nvram_get_x("","sqm_up"); %>" placeholder="e.g. 45000" />
				</td>
			</tr>

			<!-- Queue Discipline -->
			<tr>
				<th>Queue Discipline</th>
				<td>
					<select name="sqm_qdisc" class="input" style="width:150px">
						<option value="fq_codel" <% nvram_match_x("","sqm_qdisc","fq_codel","selected"); %>>HTB + fq_codel</option>
						<option value="cake"     <% nvram_match_x("","sqm_qdisc","cake",    "selected"); %>>CAKE</option>
					</select>
				</td>
			</tr>

			<!-- Overhead -->
			<tr>
				<th>Overhead (bytes)</th>
				<td>
					<input type="text" maxlength="5" class="input" size="15" name="sqm_overhead"
						value="<% nvram_get_x("","sqm_overhead"); %>" placeholder="0" />
					<span style="color:#888;font-size:11px;">(PPPoE: 8, VDSL: 8-40, WiFi: 30)</span>
				</td>
			</tr>

			<!-- Priority Preset -->
			<tr>
				<th>Priority Preset
					<br/><span style="color:#888;font-size:11px;font-weight:normal;">ECN + DSCP tự động</span>
				</th>
				<td>
					<select name="sqm_preset" id="sqm_preset_select" class="input"
						style="width:200px" onchange="change_preset()">
						<option value="none"      <% nvram_match_x("","sqm_preset","none",     "selected"); %>>None (tắt priority)</option>
						<option value="gaming"    <% nvram_match_x("","sqm_preset","gaming",   "selected"); %>>🎮 Gaming</option>
						<option value="streaming" <% nvram_match_x("","sqm_preset","streaming","selected"); %>>📺 Streaming</option>
						<option value="wfh"       <% nvram_match_x("","sqm_preset","wfh",      "selected"); %>>💼 Work From Home</option>
						<option value="balanced"  <% nvram_match_x("","sqm_preset","balanced", "selected"); %>>⚖️ Balanced</option>
						<option value="custom"    <% nvram_match_x("","sqm_preset","custom",   "selected"); %>>⚙️ Custom</option>
					</select>
					<br/>
					<span id="preset_desc" style="color:#888;font-size:11px;"></span>
				</td>
			</tr>

			<!-- Custom ports (chỉ hiện khi chọn Custom) -->
			<tr id="custom_ports_row" style="display:none;">
				<th>Custom UDP Ports
					<br/><span style="color:#888;font-size:11px;font-weight:normal;">Cách nhau bằng dấu phẩy</span>
				</th>
				<td>
					<input type="text" maxlength="200" class="input" size="35" name="sqm_game_ports"
						value="<% nvram_get_x("","sqm_game_ports"); %>"
						placeholder="5000-5060,8001-8002,27015" />
					<br/><span style="color:#888;font-size:11px;">
						Liên Quân: 5000-5060,8001-8002 &nbsp;|&nbsp;
						PUBG: 10012 &nbsp;|&nbsp;
						DOTA2: 27015-27030
					</span>
				</td>
			</tr>

		</table>
		</div><!-- sqm_settings -->

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

		</div><!-- round_bottom -->
	</div><!-- box -->
	</div></div>
	</div><!-- span9 -->
</div><!-- row-fluid -->
</div><!-- container -->
</form>

<div id="footer"></div>
</div><!-- wrapper -->
</body>
</html>
