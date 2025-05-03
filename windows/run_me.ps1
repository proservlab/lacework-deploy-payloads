# variable from jinja2 template 
$environment = "%%{ environment }%%"
$deployment = "%%{ deployment }%%"
$attacker_instances = "%%{ attacker_instances }%%"
$target_instances = "%%{ target_instances }%%"
$attacker_k8s_services = "%%{ attacker_k8s_services }%%"
$target_k8s_services = "%%{ target_k8s_services }%%"

echo "${environment}:${deployment}" > C:\\Windows\\Temp\\run_me.log
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${attacker_instances}")) | Out-File -FilePath C:\\Windows\\Temp\\attacker_instances.log -Append
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${target_instances}")) | Out-File -FilePath C:\\Windows\\Temp\\target_instances.log -Append
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${attacker_k8s_services}")) | Out-File -FilePath C:\\Windows\\Temp\\attacker_k8s_services.log -Append
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${target_k8s_services}")) | Out-File -FilePath C:\\Windows\\Temp\\target_k8s_services.log -Append