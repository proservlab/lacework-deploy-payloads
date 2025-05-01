# variable from jinja2 template 
$environment = "%%{ environment }%%"
$deployment = "%%{ deployment }%%"  

echo "${environment}:${deployment}" > C:\\Windows\\Temp\\run_me.log