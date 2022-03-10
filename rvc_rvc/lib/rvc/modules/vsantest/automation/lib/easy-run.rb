require 'yaml'
require 'fileutils'
require 'timeout'
require 'shellwords'
require_relative "rvc-util.rb"
require_relative "util.rb"

@log_file = "#{$log_path}/easy-run.log"
host_num = _get_deploy_hosts_list.count
ftt = 1
policy_valid = false
policy_rule_map = {}
default_policy_rule_map = {}
default_policy_ftt = 1
policy_ftt = 1
ratio = 0.25
disk_init = "ZERO"
_test_time = 3600
_warmup_time = 1800
@dedup = 0

vsan_datastores = _get_vsandatastore_in_cluster
if vsan_datastores == {}
  puts "------------------------------------------------------------------------------",@log_file
  puts "vSAN Is Not Enabled in Cluster #{$cluster_name}!",@log_file
  puts "------------------------------------------------------------------------------",@log_file
  exit(255)
else
  local_vsan = ""
  vsan_datastore_names = vsan_datastores.keys & $datastore_names
  if vsan_datastore_names.empty?
    puts "------------------------------------------------------------------------------",@log_file
    puts "vSAN Datastore not specified!",@log_file
    puts "------------------------------------------------------------------------------",@log_file
    exit(255)
  end
  vsan_datastore_names.each do |vsan_datastore_name|
    if vsan_datastores[vsan_datastore_name]["local"]
      local_type = "Local"
      local_vsan = vsan_datastore_name
    else
      local_type = "Remote"
    end
    puts "vSAN #{local_type} Datastore Name: #{vsan_datastore_name}", @log_file
    if disk_init == "ZERO"
      temp_cluster = _get_vsan_cluster_from_datastore(vsan_datastore_name)
      vsan_stats_hash = _get_vsan_disk_stats(temp_cluster)
      @dedup = vsan_stats_hash["Dedupe Scope"]
      vsan_type = vsan_stats_hash["vSAN type"]
      disk_init = "RANDOM" if @dedup != 0
    end
  end

  cluster_to_pick = $cluster_name
  #choose which datastore to pick to calculate the easy-run parameters
  vsan_datastore_name = ""
  if local_vsan != ""
    vsan_datastore_name = local_vsan
  else
    vsan_datastore_name = vsan_datastore_names[0]
    remote_cluster_name = _get_vsan_cluster_from_datastore(vsan_datastore_name)
    cluster_to_pick = remote_cluster_name
  end

  puts "Picking vSAN Datastore Name: #{vsan_datastore_name}", @log_file
  policy_name, rules = _get_vsan_default_policy(vsan_datastore_name)
  puts "vSAN Default Policy: #{rules}", @log_file
  rules.each do |rule|
    rule = rule.delete(' ')
    if not rule.include? "Rule-Set"
      default_policy_rule_map[rule.split(":").first] = rule.split(":").last
    end
  end
  policy_pftt = default_policy_rule_map["VSAN.hostFailuresToTolerate"] || "1"
  policy_sftt = default_policy_rule_map["VSAN.subFailuresToTolerate"] || "0"
  policy_csc = default_policy_rule_map["VSAN.checksumDisabled"] || "false"
  default_policy_ftt = ( policy_pftt.to_i + 1 ) * ( policy_sftt.to_i + 1 )

  if $storage_policy and not $storage_policy.empty? and not $storage_policy.strip.empty?
    rules = _get_storage_policy_rules($storage_policy)
    puts "Self-defined policy: #{rules}", @log_file
    rules.each do |rule|
      rule = rule.delete(' ')
      if not rule.include? "Rule-Set"
        policy_rule_map[rule.split(":").first] = rule.split(":").last
      end
    end
    policy_pftt = policy_rule_map["VSAN.hostFailuresToTolerate"] || "1"
    policy_sftt = policy_rule_map["VSAN.subFailuresToTolerate"] || "0"
    policy_csc = policy_rule_map["VSAN.checksumDisabled"] || "false"
    policy_ftt = ( policy_pftt.to_i + 1 ) * ( policy_sftt.to_i + 1 )
    policy_valid = true  
  end
  if policy_valid 
    ftt = policy_ftt.to_i
  else
    ftt = default_policy_ftt.to_i
  end
end

vsan_stats_hash = _get_vsan_disk_stats(cluster_to_pick)
total_cache_size = vsan_stats_hash["Total_Cache_Size"]
num_of_dg = vsan_stats_hash["Total number of Disk Groups"]
num_of_cap = vsan_stats_hash["Total number of Capacity Drives"]
dedup = vsan_stats_hash["Dedupe Scope"]
vsan_type = vsan_stats_hash["vSAN type"]

temp_cl_path, temp_cl_path_escape = _get_cl_path(cluster_to_pick)
witness = `rvc #{$vc_rvc} --path #{temp_cl_path_escape} -c 'vsantest.vsan_hcibench.cluster_info .' -c 'exit' -q | grep -E "^Witness Host:"`.chomp 

puts "Total Cache Size: #{total_cache_size} \n
Total number of Disk Groups: #{num_of_dg} \n
Total number of Capacity Drives: #{num_of_cap} \n
vSAN type: #{vsan_type} \n
Dedupe Scope: #{@dedup}", @log_file

if witness != ""
  puts "#{witness}", @log_file
  num_of_dg -= 1
end

if vsan_type == "All-Flash"
  total_cache_size = [num_of_dg * 600,total_cache_size].min
  ratio = 0.75
end

vm_deployed_size = total_cache_size * ratio / ftt
@vm_num = num_of_dg * 2 * $total_datastore
@data_disk_num = 8 #num_of_cap * 2 / vm_num

#if @vm_num % host_num != 0
#  @vm_num += (host_num - @vm_num % host_num)
#end

thread_num = 32 / @data_disk_num
@disk_size = [(vm_deployed_size / (@vm_num / $total_datastore * @data_disk_num)).floor,1].max
time = Time.now.to_i

pref = "hci-vdb"
if $tool == "fio"
  pref = "hci-fio"
end

vcpu = 4
size_ram = 8

`sed -i "s/^vm_prefix.*/vm_prefix: '#{pref}'/g" /opt/automation/conf/perf-conf.yaml`
`sed -i "s/^number_vm.*/number_vm: #{@vm_num}/g" /opt/automation/conf/perf-conf.yaml`
`sed -i "s/^number_cpu.*/number_cpu: #{vcpu}/g" /opt/automation/conf/perf-conf.yaml`
`sed -i "s/^size_ram.*/size_ram: #{size_ram}/g" /opt/automation/conf/perf-conf.yaml`
`sed -i "s/^number_data.*/number_data_disk: #{@data_disk_num}/g" /opt/automation/conf/perf-conf.yaml`
`sed -i "s/^size_data.*/size_data_disk: #{@disk_size}/g" /opt/automation/conf/perf-conf.yaml`
`sed -i "s/^warm_up_disk_before_.*/warm_up_disk_before_testing: '#{disk_init}'/g" /opt/automation/conf/perf-conf.yaml`
`rm -rf /opt/tmp/tmp* ; mkdir -m 755 -p /opt/tmp/tmp#{time}` 

devider = 4
if policy_csc == "true"
  devider = 1
end

gotodir = "cd /opt/automation/#{$tool}-param-files;"
executable = "fioconfig create"

if $tool == "vdbench"
  executable = "sh /opt/automation/generate-vdb-param-file.sh"
end

workloadParam = ""
for workload in $workloads
  case workload
  when "4k70r"
    workloadParam = " -n #{@data_disk_num} -w 100 -t #{thread_num} -b 4k -r 70 -s 100 -e #{_test_time} -m #{_warmup_time}"
  when "4k100r"
    workloadParam = " -n #{@data_disk_num} -w 100 -t #{thread_num} -b 4k -r 100 -s 100 -e #{_test_time} -m #{_warmup_time}"
  when "8k50r"
    workloadParam = " -n #{@data_disk_num} -w 100 -t #{thread_num} -b 8k -r 50 -s 100 -e #{_test_time} -m #{_warmup_time}"
  when "256k0r"
    workloadParam = " -n #{@data_disk_num} -w 100 -t #{thread_num/devider} -b 256k -r 0 -s 0 -e #{_test_time} -m #{_warmup_time}"
  end
  puts `#{gotodir + executable + workloadParam}`,@log_file
  `FILE=$(ls /opt/automation/#{$tool}-param-files/ -tr | grep -v / |tail -1); cp /opt/automation/#{$tool}-param-files/${FILE} /opt/tmp/tmp#{time}`
end

`sed -i "s/^self_defined_param.*/self_defined_param_file_path: '\\/opt\\/tmp\\/tmp#{time}' /g" /opt/automation/conf/perf-conf.yaml`
`sed -i "s/^output_path.*/output_path: 'easy-run-#{time}'/g" /opt/automation/conf/perf-conf.yaml`
`sed -i "s/^testing_duration.*/testing_duration:/g" /opt/automation/conf/perf-conf.yaml`
`sed -i "s/^cleanup_vm.*/cleanup_vm: false/g" /opt/automation/conf/perf-conf.yaml`
`sync; sleep 1`
`ruby #{$allinonetestingfile}`
`rm -rf /opt/tmp/tmp#{time}`
