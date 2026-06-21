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

<script>
var $j = jQuery.noConflict();

$j(document).ready(function() {
	init_itoggle('sqm_enable', change_sqm_enabled);
});
</script>

<script>
<% login_state_hook(); %>

function initial() {
	show_banner(2);
	show_menu(5, 21);
	show_footer();
	load_body();
	change_sqm_enabled();
}

function change_sqm_enabled() {
	var enabled = document.getElementById('sqm_enable_1').checked;
	showhide_div('sqm_settings', enabled ? 1 : 0);
}

function validate_bandwidth(field, name) {
	var val = parseInt(field.value);
	if (isNaN(val) || val < 1 || val > 1000000) {
		alert(name + ': Please enter a value between 1 and 1000000 kbps.');
		field.focus();
		field.select();
		return false;
	}
	return true;
}

function applyRule() {
	if (!validForm()) return;
	showLoading();
	document.form.action_mode.value = " Apply ";
	document.form.current_page.value = "/Advanced_SQM_Content.asp";
	document.form.next_page.value = "";
	document.form.action_script.value = "restart_sqm";
	document.form.submit();
}

function validForm() {
	var enabled = document.getElementById('sqm_enable_1').checked;
	if (!enabled) return true;

	if (!validate_bandwidth(document.form.sqm_down, 'Download bandwidth'))
		return false;
	if (!validate_bandwidth(document.form.sqm_up, 'Upload bandwidth'))
		return false;

	var iface = document.form.sqm_iface.value.trim();
	if (iface.length === 0) {
		alert('Please enter a WAN interface name (e.g. eth3).');
		document.form.sqm_iface.focus();
		return false;
	}

	return true;
}

function done_validating(action) {
	refreshpage();
}
</script>

</head>

<body onload="initial();" class="bg">
<div id="wrapper">
	<div id="topbar"></div>
	<div id="mainWrapper">

	<form method="post" name="form" action="/start_apply.htm" target="hidden_frame">
	<input type="hidden" name="current_page" value="/Advanced_SQM_Content.asp">
	<input type="hidden" name="next_page" value="">
	<input type="hidden" name="action_mode" value="">
	<input type="hidden" name="action_script" value="restart_sqm">
	<input type="hidden" name="action_wait" value="5">
	<input type="hidden" name="preferred_lang" value="<% nvram_get_x("", "preferred_lang"); %>">
	<input type="hidden" name="firmver" value="<% nvram_get_x("", "firmver"); %>">

	<div id="pageWrapper">
		<div id="mainMenu"></div>
		<div id="tabMenu" class="submenuBlock"></div>

		<div class="contentBlock">
			<div id="tabExplain"></div>
			<div class="container-fluid">
				<div class="row-fluid">
					<div class="span3">
						<div id="mainDescription">
							<b>Smart Queue Management (SQM)</b>
							<br><br>
							SQM uses HTB + fq_codel to reduce bufferbloat and improve latency under load.
							<br><br>
							Set download and upload bandwidth slightly below your actual line speed (90-95%).
						</div>
					</div>

					<div class="span9">

						<!-- Enable/Disable -->
						<table width="100%" cellpadding="4" cellspacing="0" class="table">
							<tr>
								<th colspan="2" style="background-color: #E3E3E3;">SQM QoS Settings</th>
							</tr>
							<tr>
								<th width="50%">Enable SQM</th>
								<td>
									<div class="main_itoggle">
										<div id="sqm_enable_on_of">
											<input type="checkbox" id="sqm_enable_fake"
												<% nvram_match_x("", "sqm_enable", "1", "value=1 checked"); %>
												<% nvram_match_x("", "sqm_enable", "0", "value=0"); %>>
										</div>
									</div>
									<div style="position: absolute; margin-left: -10000px;">
										<input type="radio" name="sqm_enable" id="sqm_enable_1" class="input" value="1"
											onclick="change_sqm_enabled();"
											<% nvram_match_x("", "sqm_enable", "1", "checked"); %>/>Yes
										<input type="radio" name="sqm_enable" id="sqm_enable_0" class="input" value="0"
											onclick="change_sqm_enabled();"
											<% nvram_match_x("", "sqm_enable", "0", "checked"); %>/>No
									</div>
								</td>
							</tr>
						</table>

						<!-- Settings (hidden when disabled) -->
						<div id="sqm_settings">
						<table width="100%" cellpadding="4" cellspacing="0" class="table">
							<tr>
								<th width="50%">WAN Interface</th>
								<td>
									<input type="text" maxlength="16" class="input" size="15"
										name="sqm_iface" style="width: 145px"
										value="<% nvram_get_x("", "sqm_iface"); %>"
										placeholder="e.g. eth3" />
									<span style="color: #888; font-size: 11px;">
										(check via SSH: <code>ip link show</code>)
									</span>
								</td>
							</tr>
							<tr>
								<th width="50%">Download Bandwidth (kbps)</th>
								<td>
									<input type="text" maxlength="10" class="input" size="15"
										name="sqm_down" style="width: 145px"
										value="<% nvram_get_x("", "sqm_down"); %>"
										placeholder="e.g. 90000" />
								</td>
							</tr>
							<tr>
								<th width="50%">Upload Bandwidth (kbps)</th>
								<td>
									<input type="text" maxlength="10" class="input" size="15"
										name="sqm_up" style="width: 145px"
										value="<% nvram_get_x("", "sqm_up"); %>"
										placeholder="e.g. 45000" />
								</td>
							</tr>
							<tr>
								<th width="50%">Queue Discipline</th>
								<td>
									<select name="sqm_qdisc" class="input" style="width: 150px">
										<option value="fq_codel" <% nvram_match_x("", "sqm_qdisc", "fq_codel", "selected"); %>>HTB + fq_codel</option>
										<option value="cake" <% nvram_match_x("", "sqm_qdisc", "cake", "selected"); %>>CAKE (if available)</option>
									</select>
								</td>
							</tr>
							<tr>
								<th width="50%">DSCP Marking</th>
								<td>
									<div class="main_itoggle">
										<div id="sqm_dscp_on_of">
											<input type="checkbox" id="sqm_dscp_fake"
												<% nvram_match_x("", "sqm_dscp", "1", "value=1 checked"); %>
												<% nvram_match_x("", "sqm_dscp", "0", "value=0"); %>>
										</div>
									</div>
									<div style="position: absolute; margin-left: -10000px;">
										<input type="radio" name="sqm_dscp" id="sqm_dscp_1" class="input" value="1"
											<% nvram_match_x("", "sqm_dscp", "1", "checked"); %>/>Yes
										<input type="radio" name="sqm_dscp" id="sqm_dscp_0" class="input" value="0"
											<% nvram_match_x("", "sqm_dscp", "0", "checked"); %>/>No
									</div>
								</td>
							</tr>
							<tr>
								<th width="50%">Overhead (bytes)</th>
								<td>
									<input type="text" maxlength="5" class="input" size="15"
										name="sqm_overhead" style="width: 145px"
										value="<% nvram_get_x("", "sqm_overhead"); %>"
										placeholder="e.g. 0" />
									<span style="color: #888; font-size: 11px;">
										(PPPoE: 8, VDSL: 8-40)
									</span>
								</td>
							</tr>
						</table>
						</div><!-- end sqm_settings -->

						<!-- Status -->
						<table width="100%" cellpadding="4" cellspacing="0" class="table">
							<tr>
								<th colspan="2" style="background-color: #E3E3E3;">Current Status</th>
							</tr>
							<tr>
								<td colspan="2">
									<pre id="sqm_status" style="font-size: 11px; background: #f5f5f5; padding: 8px; border-radius: 4px; max-height: 150px; overflow-y: auto;">
Run "sqm.sh status" via SSH to check
									</pre>
								</td>
							</tr>
						</table>

						<!-- Apply button -->
						<table class="table">
							<tr>
								<td style="border: 0 none;">
									<center>
										<input class="btn btn-primary" style="width: 219px"
											onclick="applyRule();" type="button" value="<#CTL_apply#>" />
									</center>
								</td>
							</tr>
						</table>

					</div><!-- span9 -->
				</div><!-- row-fluid -->
			</div><!-- container-fluid -->
		</div><!-- contentBlock -->
	</div><!-- pageWrapper -->
	</form>

	<div id="footer"></div>
	</div>
</div>

<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>
</body>
</html>
