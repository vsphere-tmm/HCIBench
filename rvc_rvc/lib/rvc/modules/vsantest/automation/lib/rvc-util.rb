require 'yaml'
require "ipaddress"
require 'fileutils'
require 'resolv'
require "json"
require 'shellwords'
require 'ipaddr'
require "cgi"
require 'open3'
require "readline"
require_relative 'ossl_wrapper'
require_relative 'util.rb'

# Load the OSSL configuration file
ossl_conf = '../conf/ossl-conf.yaml'

$basedir=File.dirname(__FILE__)
entry = YAML.load_file("#$basedir/../conf/perf-conf.yaml")
#Param Def
$ip_prefix = entry["static_ip_prefix"]
$ip_Address = `ip a show dev eth0 | grep global | awk {'print $2'} | cut -d "/" -f1`.chomp
$docker_ip = `ip a show dev docker0 | grep global | awk {'print $2'} | cut -d "/" -f1`.chomp
$vc_ip = entry["vc"]

begin
  Gem.load_yaml
  osc = YAML.load_file(File.join($basedir, ossl_conf)).each_with_object({}) { |(k, v), m| m[k.to_sym] = v }
rescue Errno::ENOENT
  STDERR.puts "Could not open ossl configuration file: #{ossl_conf} error: file does not exist"
  exit(1)
rescue StandardError => e
  STDERR.puts "Culd not open ossl configuration file: #{ossl_conf} error: #{e}"
  exit(1)
end

vcp = entry["vc_password"]
if vcp
  begin
    osw = OSSLWrapper.new(osc)
    $vc_password = vcp.nil? || vcp.empty? ? '' : osw.decrypt(vcp)
  rescue StandardError => e
    STDERR.puts "Could not decrypt vCenter Password: Please re-save the vCenter Password.\nError: #{e}"
    exit(1)
  end
else
  $vcp_password = ''
end

$clear_cache = entry["clear_cache"]
$vsan_debug = entry["vsan_debug"]

hp = entry["host_password"]
if $clear_cache or $vsan_debug
  if hp
    begin
      osw = OSSLWrapper.new(osc)
      $host_password = hp.nil? || hp.empty? ? '' : osw.decrypt(hp)
    rescue StandardError => e
      STDERR.puts "Could not open decrypt Host Password: Please re-save the Host Password.\nError: #{e}"
      exit(1)
    end
  else
    $host_password = ''
  end
end

$vc_username = entry["vc_username"]
$easy_run = entry["easy_run"]
$dc_name = entry["datacenter_name"].gsub("%","%25").gsub("/","%2f").gsub("\\","%5c")
$cluster_name = entry["cluster_name"].gsub("%","%25").gsub("/","%2f").gsub("\\","%5c")
$storage_policy = (entry["storage_policy"] || "").gsub('\\', '\\\\\\').gsub('"', '\"')
$resource_pool_name = (entry["resource_pool_name"] || "" ).gsub("%","%25").gsub("/","%2f").gsub("\\","%5c")
$resource_pool_name_escape = Shellwords.escape((entry["resource_pool_name"] || "" ).gsub("%","%25").gsub("/","%2f").gsub("\\","%5c"))
$fd_name = entry["vm_folder_name"] || ""
$vm_folder_name = Shellwords.escape(entry["vm_folder_name"] || "")
$network_name = (entry["network_name"] || "VM Network").gsub("%","%25").gsub("/","%2f").gsub("\\","%5c")
$datastore_names = entry["datastore_name"].map!{|ds|ds.gsub("%","%25").gsub("/","%2f").gsub("\\","%5c")}
$deploy_on_hosts = entry["deploy_on_hosts"]
$tool = entry["tool"]
$vm_prefix = entry["vm_prefix"] || $tool
$tvm_prefix = "hci-tvm"
$folder_name = "#{$vm_prefix}-#{$cluster_name}-vms".gsub("%","%25").gsub("/","%2f").gsub("\\","%5c")
$tvm_folder_name = "#{$tvm_prefix}-#{$cluster_name}-vms".gsub("%","%25").gsub("/","%2f").gsub("\\","%5c")
$all_hosts = entry["hosts"]
$host_username = entry["host_username"]
$vm_num = entry["number_vm"]
$tvm_num = 0
$num_cpu = entry["number_cpu"] || 4
$size_ram = entry["size_ram"] || 8
$number_data_disk = entry["number_data_disk"]
$size_data_disk = entry["size_data_disk"]
$self_defined_param_file_path = entry["self_defined_param_file_path"]
$warm_up_disk_before_testing = entry["warm_up_disk_before_testing"]
$testing_duration = entry["testing_duration"]
$static_enabled = entry["static_enabled"]
$output_path = entry["output_path"]
$output_path_dir = "/opt/output/results/" + $output_path
$reuse_vm = entry["reuse_vm"]
$cleanup_vm = entry["cleanup_vm"]
$workloads = entry["workloads"] || ["4k70r"]
$multiwriter = entry["multi_writer"] || false
#File path def
$allinonetestingfile = "#{$basedir}/all-in-one-testing.rb"
$cleanupfile = "#{$basedir}/cleanup-vm.rb"
$cleanuptvmfile = "#{$basedir}/cleanup-tvm.rb"
$cleanupinfolderfile = "#{$basedir}/cleanup-vm-in-folder.rb"
$credentialconffile = "#{$basedir}/../conf/credential.conf"
$deployfile = "#{$basedir}/deploy-vms.rb"
$deploytvmfile = "#{$basedir}/deploy-tvm.rb"
$dropcachefile = "#{$basedir}/drop-cache.rb"
$easyrunfile = "#{$basedir}/easy-run.rb"
$getipfile = "#{$basedir}/get-vm-ip.rb"
$gettvmipfile = "#{$basedir}/get-tvm-ip.rb"
$getxlsvdbenchfile = "#{$basedir}/get-xls-vdbench.rb"
$getxlsfiofile = "#{$basedir}/get-xls-fio.rb"
$getcpuusagefile = "#{$basedir}/getCpuUsage.rb"
$getramusagefile = "#{$basedir}/getRamUsage.rb"
$getvsancpuusagefile = "#{$basedir}/getPCpuUsage.rb"
$healthfile = "#{$basedir}/vm-health-check.rb"
$testfile = "#{$basedir}/io-test.rb"
$vmlistfile = "#{$basedir}/../tmp/vm.yaml"
$tvmlistfile = "#{$basedir}/../tmp/tvm.yaml"
$warmupfile = "#{$basedir}/disk-warm-up.rb"
$warmuptempfile = "#{$basedir}/../tmp/warmedup.tmp"
$parsefiofile = "#{$basedir}/parseFioResult.rb"
$parsevdbfile = "#{$basedir}/parseVdbResult.rb"
$generatereport = "#{$basedir}/generate_report.rb"
$getvsaninfo = "#{$basedir}/get-vsan-info.rb"

#Dir path def
$tmp_path = "#{$basedir}/../tmp/"
$log_path = "#{$basedir}/../logs/"
$vdbench_source_path = "/opt/output/vdbench-source"
$fio_source_path = "/opt/output/fio-source"
$compute_only_cluster = "" 
$total_datastore = $datastore_names.count
if IPAddress.valid? $vc_ip and IPAddress.valid_ipv6? $vc_ip
  $vc_rvc = Shellwords.escape("#{$vc_username}:#{$vc_password}") + "@[#{$vc_ip}]" + " -a"
else
  $vc_rvc = Shellwords.escape("#{$vc_username}:#{$vc_password}") + "@#{$vc_ip}" + " -a"
end
$occupied_ips = []
ENV['GOVC_USERNAME'] = "#{$vc_username}"
ENV['GOVC_PASSWORD'] = "#{$vc_password}"
if IPAddress.valid? $vc_ip and IPAddress.valid_ipv6? $vc_ip
  ENV['GOVC_URL'] = "[#{$vc_ip}]"
else
  ENV['GOVC_URL'] = "#{$vc_ip}"
end
ENV['GOVC_INSECURE'] = "true"
ENV['GOVC_DATACENTER'] = "#{$dc_name}"
ENV['GOVC_PERSIST_SESSION'] = "true"
$vm_num = 0 unless $vm_num
$vms_perstore = $vm_num / $total_datastore

$eth1_ip = ""
$vm_yaml_file = "#{$basedir}/../tmp/vm.yaml"
if $static_enabled and $ip_prefix.include? "Customize"
  $starting_static_ip = $ip_prefix.split(" ")[1].split("/")[0]
  $static_ip_size = $ip_prefix.split(" ")[1].split("/")[1]
elsif $static_enabled
  $starting_static_ip = $ip_prefix + ".0.1"
  $static_ip_size = "18"
end

$dc_path = ""
$cl_path = ""
$ip_pool = []
$vsan_perf_diag = false
$cluster_hosts_map = {}
$all_vsan_clusters = []
$all_vsan_lsom_clusters = []
$vsandatastore_in_cluster = {}
$hosts_deploy_list = []
$easy_run_vsan_cluster = ""
#clusters will be running grafana, should be called when cluster has ps enabled and against vsan datastore, if this will be used, local should always be the case
$telegraf_target_clusters_map = {}
#clusters will be running observer, should be called all the time to the local, along with remote vsan ds specified
$observer_target_clusters_arr = [$cluster_name]
$perfsvc_master_nodes = []

class MyJSON
  def self.valid?(value)
    result = JSON.parse(value)
    result.is_a?(Hash) || result.is_a?(Array)
  rescue JSON::ParserError, TypeError
    false
  end
end

def _save_str_to_hash_arr obj_str
  json_temp = ""
  hash_arr = []
  obj_str.each_line do |line|
    json_temp += line
    if MyJSON.valid?(json_temp)
      hash_arr << JSON.parse(json_temp)
      json_temp = ""
    end
  end
  return hash_arr
end

def _is_duplicated object_type, object_name
  object_name_escaped = Shellwords.escape(object_name)
  types = {"dc" => "d", "rp" => "p", "ds" => "s", "nt" => "n", "fd" => "f", "cl" => "c", "hs" => "h"}
  stdout, stderr, status = Open3.capture3(%{govc find -dc "#{Shellwords.escape($dc_name)}" -type #{types[object_type]} -name "#{object_name_escaped}"})
  if stderr != ""  
    return true, stderr
  elsif stdout.chomp.split("\n").size != 1 #_save_str_to_hash_arr(stdout).size != 1
    return true, "Found #{stdout.chomp.split("\n").size} #{object_name}"
  else
    return false,""
  end
end

def _has_resource object_type, object_name
  object_name_escaped = Shellwords.escape(object_name)
  types = {"dc" => "d", "rp" => "p", "ds" => "s", "nt" => "n", "fd" => "f", "cl" => "c", "hs" => "h"}
  return (`govc find -type #{types[object_type]} -dc "#{Shellwords.escape($dc_name)}" -name "#{object_name_escaped}"`.chomp != "")
end

def _get_folder_moid(folder_name, parent_moid = "")
  return "" if folder_name == ""
  folder_name_escaped = Shellwords.escape(folder_name)
  if parent_moid == ""
    parent_moid = `govc find -type f -i -dc "#{Shellwords.escape($dc_name)}" . -parent "#{_get_moid('dc',$dc_name).join(':')}" -name "vm"`.chomp
  end
  return `govc find -type f -i -dc "#{Shellwords.escape($dc_name)}" . -parent "#{parent_moid}" -name "#{folder_name_escaped}"`.chomp
=begin
  parent_moid = ""
  if parent_name != "" #get parent fd's moid
    parent_moid = _get_moid("fd",parent_name).join(":")
  else
    parent_moid = `govc find -type f -i -dc "#{Shellwords.escape($dc_name)}" . -parent "#{_get_moid('dc',$dc_name).join(':')}" -name "vm"`.chomp
  end
  return `govc find -type f -i -dc "#{Shellwords.escape($dc_name)}" . -parent "#{parent_moid}" -name "#{folder_name_escaped}"`.chomp
=end
end

def _get_moid object_type, object_name
  object_name_escaped = Shellwords.escape(object_name)
  types = {"dc" => "d", "rp" => "p", "ds" => "s", "nt" => "n", "fd" => "f", "cl" => "c", "hs" => "h"}
  if not _is_duplicated(object_type, object_name)[0]
    path = "./"
    path = "/" if object_type == "dc"
    obj_js = JSON.parse(`govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s -json -type #{types[object_type]} #{path} -name "#{object_name_escaped}"`.chomp)
    obj_type = obj_js["Obj"]["Type"]
    obj_id = obj_js["Obj"]["Value"]
    return obj_type,obj_id
  else
    return "",""
  end
end

def _get_name object_type, object_moid
  return `govc object.collect -s #{object_type}:#{object_moid} name`.chomp
end

def _get_dc_path
  if $dc_path != ""
    return $dc_path, $dc_path_escape 
  else
    ENV['GOVC_DATACENTER'] = ""
    $dc_path = `govc find -type d -name "#{Shellwords.escape($dc_name)}"`.chomp
    $dc_path = $dc_path.encode('UTF-8', :invalid => :replace)[1..-1] if $dc_path != ""
    $dc_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}")
  end
  ENV['GOVC_DATACENTER'] = "#{$dc_name}"
  return $dc_path, $dc_path_escape
end

def _get_cl_path(cluster_name = $cluster_name)
  return $cl_path, $cl_path_escape if (cluster_name == $cluster_name) and $cl_path != ""
  $dc_path, $dc_path_escape = _get_dc_path
  @computer_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/computers")
  cl_path = ""
  cl_arr = `rvc #{$vc_rvc} --path #{@computer_path_escape} -c 'find .' -c 'exit' -q`.encode('UTF-8', :invalid => :replace).split("\n")
  cl_arr.each do |cl|
    if cl[/#{Regexp.escape cluster_name}$/] and (cl.partition(' ').last == cluster_name or cl.split('/').last == cluster_name)
      cl_path = "computers/#{cl.partition(' ').last}"
    end
  end
  cl_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/#{cl_path}") if cl_path != ""
  if cluster_name == $cluster_name
    $cl_path = cl_path
    $cl_path_escape = cl_path_escape
  end
  return cl_path, cl_path_escape
end

def _get_folder_path_escape
  $dc_path, $dc_path_escape = _get_dc_path
  folder_path_escape = ""
  folder_path_escape_gsub = ""
  if $fd_name and $fd_name != ""
    folder_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/vms/#{$fd_name}/#{$vm_prefix}-#{$cluster_name}-vms")
    folder_path_escape_gsub = Shellwords.escape("/#{$vc_ip}/#{$dc_path.gsub('"','\"')}/vms/#{$fd_name.gsub('"','\"')}/#{$vm_prefix}-#{$cluster_name.gsub('"','\"')}-vms")
  else
    folder_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/vms/#{$vm_prefix}-#{$cluster_name}-vms")
    folder_path_escape_gsub = Shellwords.escape("/#{$vc_ip}/#{$dc_path.gsub('"','\"')}/vms/#{$vm_prefix}-#{$cluster_name.gsub('"','\"')}-vms")
  end
  
  #`govc object.mv -dc "#{Shellwords.escape($dc_name)}" '#{_get_moid("fd",$fd_name).join(":")}' "Folder:group-v805" `

  return folder_path_escape, folder_path_escape_gsub
end

def _get_tvm_folder_path_escape
  $dc_path, $dc_path_escape = _get_dc_path
  tvm_folder_path_escape = ""
  tvm_folder_path_escape_gsub = ""
  if $fd_name and $fd_name != ""
    tvm_folder_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/vms/#{$fd_name}/#{$tvm_prefix}-#{$cluster_name}-vms")
    tvm_folder_path_escape_gsub = Shellwords.escape("/#{$vc_ip}/#{$dc_path.gsub('"','\"')}/vms/#{$fd_name.gsub('"','\"')}/#{$tvm_prefix}-#{$cluster_name.gsub('"','\"')}-vms")
  else
    tvm_folder_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/vms/#{$tvm_prefix}-#{$cluster_name}-vms")
    tvm_folder_path_escape_gsub = Shellwords.escape("/#{$vc_ip}/#{$dc_path.gsub('"','\"')}/vms/#{$tvm_prefix}-#{$cluster_name.gsub('"','\"')}-vms")
  end
  return tvm_folder_path_escape, tvm_folder_path_escape_gsub
end

#returning all [hosts] in the cluster
def _get_hosts_list(cluster_name = $cluster_name)
  hosts_list = []
  host_system_id_arr = `govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{_get_moid("cl",cluster_name).join(":")} host`.chomp.split(",")
  host_system_id_arr.each do |host_system_id|
    hosts_list << `govc object.collect -s #{host_system_id} name`.chomp
  end
  return hosts_list
end

#returning [host] for vm to deploy w/o ds restriction
def _get_deploy_hosts_list
  return $hosts_deploy_list if $hosts_deploy_list != []
  if $deploy_on_hosts
    $hosts_deploy_list = $all_hosts 
  else
    $hosts_deploy_list = _get_hosts_list
  end
  return $hosts_deploy_list
end

def _get_hosts_list_in_ip(cluster_name = $cluster_name)
  hosts = _get_hosts_list(cluster_name)
  hosts.map!{|host| _get_ip_from_hostname(host)}
  return hosts
end

def _get_hosts_list_by_ds_name(datastore_name)
  hosts_list = []
  host_system_hash = JSON.parse(`govc object.collect -json -s #{_get_moid("ds",datastore_name).join(":")} host`.chomp)
  host_system_hash[0]["Val"]["DatastoreHostMount"].each do |host_system|
    if host_system["MountInfo"]["Accessible"]
      obj_type = host_system["Key"]["Type"]
      obj_id = host_system["Key"]["Value"]
      hosts_list << _get_name(obj_type, obj_id)
    end
  end
  return hosts_list
end

def _get_hosts_list_by_ds_name_in_ip(datastore_name)
  hosts_list = _get_hosts_list_by_ds_name(datastore_name)
  hosts_list.map!{|host| _get_ip_from_hostname(host)}
  return hosts_list
end

def _ssh_to_vm
vm_entry = YAML.load_file("#{$vm_yaml_file}")
vms = vm_entry["vms"]
  for vm in vms
    `sed -i '/#{vm} /d' /root/.ssh/known_hosts`
    `echo -n "#{vm} " >> /root/.ssh/known_hosts`
    `echo -n "\`cat /opt/output/vm-template/vm-key\`\n" >>  /root/.ssh/known_hosts`
  end
  return vms
end

def _get_ds_path_escape(datastore_name)
  $dc_path, $dc_path_escape = _get_dc_path
  ds_path = ""
  ds_path_escape = ""
  datastores_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/datastores")
  ds_arr =  `rvc #{$vc_rvc} --path #{datastores_path_escape} -c 'find .' -c 'exit' -q`.encode('UTF-8', :invalid => :replace).split("\n")
  ds_arr.each do |ds|
    if ds[/#{Regexp.escape datastore_name}$/] and ds.partition(' ').last.gsub(/^.*\//,"") == datastore_name
      ds_path = "datastores/#{ds.partition(' ').last}"
    end
  end
  ds_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/#{ds_path}")
  ds_path = "/#{$vc_ip}/#{$dc_path}/" + ds_path
  return ds_path, ds_path_escape
end

def _is_vsan(datastore_name)
  ds_type_js = JSON.parse(`govc object.collect -dc "#{Shellwords.escape($dc_name)}" -json #{_get_moid("ds",datastore_name).join(':')} summary.type`.chomp)
  ds_type = ds_type_js[0]["Val"]
  return (ds_type == "vsan")
end

def _is_ps_enabled(cluster_name = $cluster_name)
  return false if $compute_only_cluster == cluster_name
  vsan_stats_hash = _get_vsan_disk_stats(cluster_name)
  return vsan_stats_hash["PerfSvc"]
end

#returning {vsan_ds1 => {"capacity"=>cap,"freeSpace"=>fs,"local"=>true/false}, vsan_ds2 => {"capacity"=>cap,"freeSpace"=>fs,"local"=>true/false}}
def _get_vsandatastore_in_cluster(cluster_name = $cluster_name)
  return $vsandatastore_in_cluster if $vsandatastore_in_cluster != {}
  datastores_full_moid_in_cluster = `govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{_get_moid("cl",cluster_name).join(":")} datastore`.chomp.split(",")
  datastores_full_moid_in_cluster.each do |datastore_full_moid|
    if `govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{datastore_full_moid} summary.type`.chomp == "vsan"
      ds_name = `govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{datastore_full_moid} name`.chomp
      ds_capacity = (`govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{datastore_full_moid} summary.capacity`.to_i/(1024**3)).to_s
      ds_freespace = (`govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{datastore_full_moid} summary.freeSpace`.to_i/(1024**3)).to_s
      $vsandatastore_in_cluster[ds_name] = {"capacity" => ds_capacity, "freeSpace" => ds_freespace, "local" => _is_ds_local_to_cluster(ds_name)}
    end
  end
  return $vsandatastore_in_cluster
end

def _get_ip_addr
  return $ip_Address
end

def _is_ip(ip)
  return !!(ip =~ Resolv::IPv4::Regex)
end

def _get_ip_from_hostname(hostname)
  address = ""
  begin
    address = IPSocket.getaddress(hostname)
  rescue Exception => e
    address = "Unresolvable"
  end
  return address
end

def _get_perfsvc_master_node(cluster_name = $cluster_name)
  hosts_list = _get_hosts_list(cluster_name)
  cmd = "python /usr/lib/vmware/vsan/perfsvc/vsan-perfsvc-status.pyc svc_info | grep 'isStatsMaster = true' | wc -l"
  hosts_list.each do |host|
    return host if ssh_valid(host,$host_username,$host_password) and ssh_cmd(host,$host_username,$host_password,cmd).chomp == "1"
  end
  return ""
end

def _set_perfsvc_verbose_mode(verbose_mode,cluster_name = $cluster_name)
  cl_path, cl_path_escape = _get_cl_path(cluster_name)
  `rvc #{$vc_rvc} --path #{cl_path_escape} -c 'vsantest.perf.vsan_cluster_perfsvc_switch_verbose . #{verbose_mode}' -c 'exit' -q`
  return ($?.exitstatus == 0)
end

def _clean_perfsvc_stats(cluster_name = $cluster_name)
  cl_path, cl_path_escape = _get_cl_path(cluster_name)
  `rvc #{$vc_rvc} --path #{cl_path_escape} -c 'vsan.perf.stats_object_delete .' -c 'exit' -q`
  return ($?.exitstatus == 0)
end

def _start_perfsvc(cluster_name = $cluster_name)
  cl_path, cl_path_escape = _get_cl_path(cluster_name)
  `rvc #{$vc_rvc} --path #{cl_path_escape} -c 'vsan.perf.stats_object_create .' -c 'exit' -q`
  return ($?.exitstatus == 0)
end

# get ip pool if using static, otherwise return []
# only add the ips not being occupied
def _get_ip_pools
  return [] if not $static_enabled
  return $ip_pool if $ip_pool != []
  ip_range = IPAddr.new("#{$starting_static_ip}/#{$static_ip_size}")
  begin_ip = IPAddr.new($starting_static_ip)
  system("ifconfig -s eth1 0.0.0.0; ifconfig eth1 down; ifconfig eth1 up")
  ips = []
  ip_required = [_get_num_of_tvm_to_deploy,_get_num_of_vm_to_deploy].max + 1 
  while ips.size < ip_required and ip_range.include? begin_ip do
    find_ip_threads = []
    count = ips.size
    temp_ip_arr = []
    while count < ip_required and ip_range.include? begin_ip do
      temp_ip_arr << begin_ip.to_s
      begin_ip = begin_ip.succ()
      count += 1
    end
    temp_ip_arr.each do |ip_to_s|
      find_ip_threads << Thread.new{
        o = system("arping -q -D -I eth1 -c 5 #{ip_to_s}")
        if o # ip available
          $occupied_ips.delete(ip_to_s) if $occupied_ips.include? ip_to_s
          ips << ip_to_s if not ips.include? ip_to_s
        else #ip occupied
          $occupied_ips << ip_to_s if not $occupied_ips.include? ip_to_s
        end
      } 
    end
    find_ip_threads.each{|t|t.join}
  end
  ips = ips.sort_by{|s| s.split(".")[-1].to_i}
  if ips[0]
    $eth1_ip = ips[0]
    system("ifconfig -s eth1 #{$eth1_ip}/#{$static_ip_size}")
  end
  $ip_pool = ips[1..-1]
  return $ip_pool
end

#despite if any ip is occupied, whether the subnet itself is big enough
def _range_big_enough
  ip_range = IPAddr.new("#{$starting_static_ip}/#{$static_ip_size}")
  temp_ip = IPAddr.new($starting_static_ip)
  ip_required = [_get_num_of_tvm_to_deploy,_get_num_of_vm_to_deploy].max + 1
  for i in 1..ip_required 
    return false if not ip_range.include? temp_ip
    temp_ip = temp_ip.succ()
  end
  return true
end

#Would only called by pre-validation
def _get_num_of_tvm_to_deploy
  return $tvm_num if $tvm_num != 0
  $tvm_num = _get_deploy_hosts_list.size  
  return $tvm_num
end

########### GOVC??????????
#Would only called by pre-validation, 
def _get_num_of_vm_to_deploy
  return $vm_num if not $easy_run
  vsan_stats_hash = _get_vsan_disk_stats(_pick_vsan_cluster_for_easy_run)
  num_of_dg = vsan_stats_hash["Total number of Disk Groups"]
  $cl_path, $cl_path_escape = _get_cl_path if $cl_path == ""
  witness = `rvc #{$vc_rvc} --path #{$cl_path_escape} -c 'vsantest.vsan_hcibench.cluster_info .' -c 'exit' -q | grep -E "^Witness Host:"`.chomp
  num_of_dg -= 1 if witness != ""
  $vm_num = num_of_dg * 2 * $total_datastore
  return $vm_num 
end

def _pick_vsan_cluster_for_easy_run
  return $easy_run_vsan_cluster if $easy_run_vsan_cluster != ""
  vsan_datastores = _get_vsandatastore_in_cluster
  vsan_datastore_names = vsan_datastores.keys & $datastore_names
  remote_cluster = []
  vsan_datastore_names.each do |vsan_datastore_name|
    if vsan_datastores[vsan_datastore_name]["local"]
      $easy_run_vsan_cluster = _get_vsan_cluster_from_datastore(vsan_datastore_name)
      return $easy_run_vsan_cluster
    else
      remote_cluster << _get_vsan_cluster_from_datastore(vsan_datastore_name)
    end
  end
  $easy_run_vsan_cluster = remote_cluster[0]
  return $easy_run_vsan_cluster
end

def _is_ds_local_to_cluster(datastore_name)
  datastore_alias_id =`govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{_get_moid("ds",datastore_name).join(":")} info.aliasOf`.chomp.delete('-')
  datastore_container_id = `govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{_get_moid("ds",datastore_name).join(":")} info.containerId`.chomp.delete('-')
  cluster_json = JSON.parse(`govc object.collect -json -s #{_get_moid("cl",$cluster_name).join(":")} configurationEx`.chomp)  
  if cluster_json[0]["Val"]["VsanHostConfig"][0]["ClusterInfo"]# ["Enabled"] 
    $compute_only_cluster = $cluster_name if not cluster_json[0]["Val"]["VsanHostConfig"][0]["Enabled"]
    cluster_id = cluster_json[0]["Val"]["VsanHostConfig"][0]["ClusterInfo"]["Uuid"].delete('-')
    return (cluster_id == datastore_container_id or cluster_id == datastore_alias_id)
  else
    return true
  end
end

# get the owner cluster of the datastore
def _get_vsan_cluster_from_datastore(datastore_name)
  datastore_alias_id =`govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{_get_moid("ds",datastore_name).join(":")} info.aliasOf`.chomp.delete('-')
  datastore_container_id = `govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{_get_moid("ds",datastore_name).join(":")} info.containerId`.chomp.delete('-')
  ds_hosts_list = _get_hosts_list_by_ds_name(datastore_name)
  ds_hosts_list.each do |host|
    cluster_id = `govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{_get_moid("hs",host).join(":")} config.vsanHostConfig.clusterInfo.uuid`.chomp.delete('-')
    if cluster_id == datastore_container_id or cluster_id == datastore_alias_id
      cluster_full_moid = `govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{_get_moid("hs",host).join(":")} parent`.chomp
      return `govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{cluster_full_moid} name`.chomp
    end
  end
end

# get compliant [ds] of the storage policy
def _get_compliant_datastore_ids_escape(storage_policy = $storage_policy)
  policy_js = JSON.parse(`govc storage.policy.info -s -json $'#{storage_policy.gsub("'",%q(\\\'))}'`.chomp)
  compliant_ds_names = policy_js["Policies"][0]["CompatibleDatastores"]
  return compliant_ds_names.map!{|ds|_get_ds_id_by_name(ds)}
end

# return datastore ref_id
def _get_ds_id_by_name(datastore_name)
  return _get_moid("ds",datastore_name)[1]
end

#clusters have vsan datastores mounted to testing cluster and those datastores are used for testing
#may not include the local cluster if only testing against remote datastores
#this would be only useful for wb clear
def _get_all_vsan_lsom_clusters
  return $all_vsan_lsom_clusters if $all_vsan_lsom_clusters != []
  vsan_datastores = _get_vsandatastore_in_cluster
  if vsan_datastores == {}
    p "vSAN is not enabled!"
    return []
  else
    vsan_datastore_names = vsan_datastores.keys & $datastore_names
    if not vsan_datastore_names.empty?
      vsan_datastore_names.each do |vsan_datastore_name|
        $all_vsan_lsom_clusters = $all_vsan_lsom_clusters | [_get_vsan_cluster_from_datastore(vsan_datastore_name)]
      end
    end
  end
  return $all_vsan_lsom_clusters
end

#clusters have vsan datastores mounted to testing cluster and those datastores are used for testing
#also must include the local cluster
#this would be only useful for all the cases except wb clear
def _get_all_vsan_clusters
  return $all_vsan_clusters if $all_vsan_clusters != []
  vsan_datastores = _get_vsandatastore_in_cluster
  if vsan_datastores == {}
    p "vSAN is not enabled!"
    return []
    #vsan is enabled, pass over all the clusters with vsan enabled
    #if remote cluster is included, it must have remote ds for testing
    #local cluster is automatically included even w/o any vsan ds being tested
  else
    $all_vsan_clusters = [$cluster_name]
    vsan_datastore_names = vsan_datastores.keys & $datastore_names
    #we at least have one vsan ds to test
    if not vsan_datastore_names.empty?
      $vsan_perf_diag = true
      vsan_datastore_names.each do |vsan_datastore_name|
        $all_vsan_clusters =  $all_vsan_clusters | [_get_vsan_cluster_from_datastore(vsan_datastore_name)]
      end
    end
  end
  return $all_vsan_clusters
end

def _get_vsan_stats(datastore_name)
  datastore_full_moid = _get_moid("ds",datastore_name).join(":")
  vsan_info_json = JSON.parse(`govc datastore.vsan.info -json -dc "#{Shellwords.escape($dc_name)}" -m #{datastore_full_moid}`.chomp)
  vsan_default_policy_id = vsan_info_json["DatastoreDefaultProfileId"][datastore_full_moid][0]
  vsan_detail = {}
  if vsan_info_json["DatastoreDefaultProfileId"][datastore_full_moid][1] != ""
    vsan_detail = JSON.parse(vsan_info_json["DatastoreDefaultProfileId"][datastore_full_moid][1])
  end
  vsan_cluster_name = vsan_info_json["DatastoreDefaultProfileId"][datastore_full_moid][2]
  return vsan_default_policy_id, vsan_detail, vsan_cluster_name
end

#returning policy_name, rules in []
def _get_vsan_default_policy(datastore_name)
  vsan_default_policy_id, _, _ = _get_vsan_stats(datastore_name)
  default_policy_hash = JSON.parse(`govc storage.policy.ls -json #{vsan_default_policy_id}`.chomp)
  policy_name = default_policy_hash["Profile"][0]["Name"]
  return policy_name, _get_storage_policy_rules(policy_name)
end

#returning rules of the storage policy in []
def _get_storage_policy_rules(storage_policy = $storage_policy)
  rules = []
  policy_js = JSON.parse(`govc storage.policy.info -s -json $'#{storage_policy.gsub("'",%q(\\\'))}'`.chomp)
  rules_js = policy_js["Policies"][0]["Profile"]["Constraints"]["SubProfiles"][0]["Capability"]
  rules_js.each do |rule_json|
    rules << "#{rule_json['Id']['Namespace']}.#{rule_json['Id']['Id']}: #{rule_json['Constraint'][0]['PropertyInstance'][0]['Value']}"
  end
  return rules
end

#returning vsan disk stats detail table stats, sum stats
def _get_vsan_disk_stats(cluster_name = $cluster_name)
  cluster_moid = _get_moid('cl',cluster_name).join(':')
  #puts `govc cluster.vsan.info -json -dc "#{Shellwords.escape($dc_name)}" -m "#{cluster_moid}"`
  vsan_stats_hash = JSON.parse(`govc cluster.vsan.info -json -dc "#{Shellwords.escape($dc_name)}" -m "#{cluster_moid}"`.chomp)
  disks = JSON.parse(vsan_stats_hash["ClusterVsanInfo"][cluster_moid])
  cache_num = 0
  cache_size = 0
  capacity_num = 0
  type = 'Hybrid'
  dedupe_scope = 0
  disks.keys.each do |disk|
    if disks[disk]["isSsd"] == 1
      cache_size += disks[disk]["ssdCapacity"]/1024**3
      cache_num += 1
      type = "All-Flash" if disks[disk]["isAllFlash"] == 1
      dedupe_scope = disks[disk]["dedupScope"] if type == "All-Flash"
    else
      capacity_num += 1
    end
  end  
  vsan_conf = vsan_stats_hash["ClusterVsanConf"][cluster_moid]
  perfsvc = vsan_conf["PerfsvcConfig"]["Enabled"]
  verbose_mode = false
  if perfsvc
    verbose_mode = vsan_conf["PerfsvcConfig"]["VerboseMode"]
  end
  return {"PerfSvc"=> perfsvc, "PerfSvc_verbose" => verbose_mode, "Total_Cache_Size"=> cache_size, "Total number of Disk Groups"=> cache_num, "Total number of Capacity Drives"=> capacity_num, "vSAN type"=>type,"Dedupe Scope"=> dedupe_scope} 
end

def _get_cluster_hosts_map_from_file(test_case_path)
  cluster_hosts_map = {}
  Dir.entries(test_case_path).select {|entry| File.directory? File.join(test_case_path,entry) and !(entry =='.' || entry == '..') and entry =~ /iotest-/}.each do |ioFolder|
    filename = test_case_path + "/#{ioFolder}/cluster_hosts_map.cfg"
    if File.exist? filename
      file_data = File.open(filename).read
      cluster_hosts_map = eval(file_data)
    else
      cluster_hosts_map = _get_cluster_hosts_map
      File.open(filename, "w") { |f| f.write cluster_hosts_map.to_s }
    end
  end
  return cluster_hosts_map
end

#returning has {cluster1 => [hosts...], cluster2 => [hosts...]}
def _get_cluster_hosts_map
  return $cluster_hosts_map if $cluster_hosts_map != {}
  @vsan_clusters = _get_all_vsan_clusters
  if not @vsan_clusters.empty?
    @vsan_clusters.each do |vsan_cluster|
      $cluster_hosts_map[vsan_cluster] = _get_hosts_list(vsan_cluster)
    end
  else
    $cluster_hosts_map[$cluster_name] = _get_hosts_list
  end
  return $cluster_hosts_map
end

# returning spare resource info of host in [cpu,ram_in_GB]
def _get_host_spare_compute_resource(host)
  resource_capacity = `govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{_get_moid("hs",host).join(":")} hardware.cpuInfo.numCpuThreads hardware.memorySize`.chomp.split("\n")
  host_cpu = resource_capacity[0].to_i
  host_ram = resource_capacity[1].to_f/(1024**2)
  vm_total_cpu = 0
  vm_total_ram = 0
  vms_moid = `govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{_get_moid("hs",host).join(":")} vm`.chomp.split(",")
  vms_moid.each do |vm_moid|
    vm_arr = `govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{vm_moid} config.hardware.numCPU config.hardware.memoryMB runtime.powerState`.chomp.split("\n").reverse()
    if vm_arr[0] == "poweredOn"
      vm_total_cpu += vm_arr[1].to_i
      vm_total_ram += vm_arr[2].to_f
    end
  end
  return [host_cpu-vm_total_cpu,((host_ram-vm_total_ram)/1024).to_i]
end

def _get_resource_used_by_guest_vms(host)
  vm_total_res = [0,0]
  vms_moid = `govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{_get_moid("hs",host).join(":")} vm`.chomp.split(",")
  vms_moid.each do |vm_moid|
    vm_arr = `govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{vm_moid} name config.hardware.numCPU config.hardware.memoryMB runtime.powerState`.chomp.split("\n").reverse()
    if vm_arr[0] == "poweredOn" and vm_arr[1] =~ /^#{$vm_prefix}-/
      vm_total_res[0] += vm_arr[2].to_i
      vm_total_res[1] += (vm_arr[3].to_f/1024).to_i
    end
  end
  return vm_total_res
end

# returning datastore capacity and free space
def _get_datastore_capacity_and_free_space(datastore_name)
  puts `govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{_get_moid("ds",datastore_name).join(":")} summary.capacity`
  ds_capacity = (`govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{_get_moid("ds",datastore_name).join(":")} summary.capacity`.to_i/(1024**3)).to_s
  ds_freespace = (`govc object.collect -dc "#{Shellwords.escape($dc_name)}" -s #{_get_moid("ds",datastore_name).join(":")} summary.freeSpace`.to_i/(1024**3)).to_s
  return ds_capacity,ds_freespace
end

def _get_cpu_usage(test_case_path)
  msg = ""
  dir = test_case_path
  _get_cluster_hosts_map
  $cluster_hosts_map.keys.each do |cluster_name|
    if File.directory?(dir)
      Dir.entries(dir).select {|entry| File.directory? File.join(dir,entry) and !(entry =='.' || entry == '..') and entry =~ /iotest-/}.each do |ioFolder|
        jsonFile_list = `find "#{dir}/#{ioFolder}"/jsonstats/pcpu/ -type f -name 'pcpu*' | grep -e "#{$cluster_hosts_map[cluster_name].join('\|')}" | grep -v thumb`
        jsonFile_list = jsonFile_list.split("\n")
        server_resource_usage_arr = []
        jsonFile_list.each do |file|
          jsonFile = open(file)
          json = jsonFile.read
          parsed = JSON.parse(json)
          each_resource_usage_arr = []
          parsed["stats"].each do |vcpu|
            arr = vcpu[1]["usedPct"]["values"]
            avg_each_vcpu = arr.inject{ |sum, el| sum + el }.to_f / arr.size
            each_resource_usage_arr.push(avg_each_vcpu)
          end
          avg_each_test_server = each_resource_usage_arr.inject{ |sum, el| sum + el }.to_f / each_resource_usage_arr.size
          server_resource_usage_arr.push(avg_each_test_server)
        end
        avg_test_case = (server_resource_usage_arr.inject{ |sum, el| sum + el }.to_f / server_resource_usage_arr.size).round(2)
        msg += "#{cluster_name}: #{avg_test_case}%; "
      end
    end
  end
  if msg.count(";") == 1
    return msg.scan(/[0-9]*.[0-9]*%/).join 
  else
    return msg
  end
end

def _get_ram_usage(test_case_path)
  msg = ""
  dir = test_case_path
  _get_cluster_hosts_map
  $cluster_hosts_map.keys.each do |cluster_name|
    if File.directory?(dir)
      Dir.entries(dir).select {|entry| File.directory? File.join(dir,entry) and !(entry =='.' || entry == '..') and entry =~ /iotest-/}.each do |ioFolder|#enter io folder
        jsonFile_list = `find "#{dir}/#{ioFolder}"/jsonstats/mem/ -type f -name 'system*' | grep -e "#{$cluster_hosts_map[cluster_name].join('\|')}"  | grep -v thumb`
        jsonFile_list = jsonFile_list.split("\n")
        server_resource_usage_arr = [] 
        jsonFile_list.each do |file|
          jsonFile = open(file)
          json = jsonFile.read
          parsed = JSON.parse(json)
          each_resource_usage_arr = []
          arr = parsed["stats"]["pctMemUsed"]["values"]
          avg_each_ram = arr.inject{ |sum, el| sum + el }.to_f / arr.size
          each_resource_usage_arr.push(avg_each_ram)
          avg_each_test_server = each_resource_usage_arr.inject{ |sum, el| sum + el }.to_f / each_resource_usage_arr.size
          server_resource_usage_arr.push(avg_each_test_server)
        end
        avg_test_case = (server_resource_usage_arr.inject{ |sum, el| sum + el }.to_f / server_resource_usage_arr.size).round(2)
        msg += "#{cluster_name}: #{avg_test_case}%; "
      end
    end
  end
  if msg.count(";") == 1
    return msg.scan(/[0-9]*.[0-9]*%/).join 
  else
    return msg
  end
end

def _get_vsan_cpu_usage(test_case_path)
  msg = ""
  dir = test_case_path
  _get_cluster_hosts_map
  $cluster_hosts_map.keys.each do |cluster_name|
    if File.directory?(dir)
      pcpu_usage=
      total_pcpu=
      dirName = File.basename(dir)
      Dir.entries(dir).select {|entry| File.directory? File.join(dir,entry) and !(entry =='.' || entry == '..') and entry =~ /iotest-/}.each do |ioFolder|#enter io folder
        jsonFile_list = `find "#{dir}/#{ioFolder}"/jsonstats/pcpu/ -type f -name 'wdtsum-*' | grep -e "#{$cluster_hosts_map[cluster_name].join('\|')}" | grep -v thumb `
        jsonFile_list = jsonFile_list.split("\n")
        file_cpu_usage_arr = [] #each element should be the avg of each server cpu_usage number
        jsonFile_list.each do |file| # get each server's cpu_usage number
          jsonFile = open(file)
          json = jsonFile.read
          begin
            parsed = JSON.parse(json)
          rescue JSON::ParserError => e
            return e
          end
          arr = parsed["stats"]["runTime"]["avgs"]
          avg_of_file = arr.inject { |sum, el| sum + el }.to_f / arr.size * 100
          file_cpu_usage_arr.push(avg_of_file)
        end
        pcpu_usage=file_cpu_usage_arr.inject{ |sum, el| sum + el }.to_f
      end
      Dir.entries(dir).select {|entry| File.directory? File.join(dir,entry) and !(entry =='.' || entry == '..') and entry =~ /iotest-/}.each do |ioFolder|#enter io folder
        jsonFile_list = `find "#{dir}/#{ioFolder}"/jsonstats/pcpu/ -type f -name 'pcpu*' | grep -e "#{$cluster_hosts_map[cluster_name].join('\|')}" | grep -v thumb`
        jsonFile_list=jsonFile_list.split("\n")
        total_num_of_pcpu = [] #each element should be the avg of each server cpu_usage number
        jsonFile_list.each do |file| # get each server's cpu_usage number
          jsonFile = open(file)
          json = jsonFile.read
          parsed = JSON.parse(json)
          total_num_of_pcpu.push(parsed["stats"].size)
        end
        total_pcpu = total_num_of_pcpu.inject{ |sum, el| sum + el }
      end
      msg += "#{cluster_name}: #{(pcpu_usage/total_pcpu).round(2)}%; " if pcpu_usage != 0.0
    end
  end
  if msg.count(";") == 1
    return msg.scan(/[0-9]*.[0-9]*%/).join 
  else
    return msg
  end
end

#Convert a string to a unicode string.
def _convert2unicode(str)
    strNew = ""
    str.split('').each { |c| strNew = strNew + '\\u' + c.ord.to_s(16).rjust(4,'0') }
    return strNew
end


