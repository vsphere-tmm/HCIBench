require 'shellwords'
require_relative "rvc-util.rb"
require_relative "util.rb"


host_num = _get_hosts_list.count
policy_rule_map = {}
default_policy_rule_map = {}

vsan_datastores = _get_vsandatastore_in_cluster
if vsan_datastores == {}
  print "vSAN is not enabled!\n"
  exit(255)
else
  vsan_datastore_names = vsan_datastores.keys & $datastore_names
  if vsan_datastore_names.empty?
    print "Not Testing on vSAN!"
    exit(255)
  end
  file = File.open("#{ARGV[0]}/vsan.cfg", 'w')
  vsan_datastore_names.each do |vsan_datastore_name|
    policy_name, rules = _get_vsan_default_policy(vsan_datastore_name)
    rules.each do |rule|
      rule = rule.delete(' ')
      if not rule.include? "Rule-Set"
        default_policy_rule_map[rule.split(":").first] = rule.split(":").last
      end
    end

    policy_ftm = "RAID-1(Mirroring)-Performance"
    if default_policy_rule_map.key?("VSAN.replicaPreference")
      policy_ftm = default_policy_rule_map["VSAN.replicaPreference"].split(" ")[-1]
    end
    policy_pftt = default_policy_rule_map["VSAN.hostFailuresToTolerate"] || "1"
    policy_sftt = default_policy_rule_map["VSAN.subFailuresToTolerate"] || "0"
    policy_csc = default_policy_rule_map["VSAN.checksumDisabled"] || "false"
    if $storage_policy and not $storage_policy.empty? and not $storage_policy.strip.empty?
      rules = _get_storage_policy_rules($storage_policy)
      rules.each do |rule|
        rule = rule.delete(' ')
        if not rule.include? "Rule-Set"
          policy_rule_map[rule.split(":").first] = rule.split(":").last
        end
      end
      if policy_rule_map.key?("VSAN.replicaPreference")
        policy_ftm = policy_rule_map["VSAN.replicaPreference"].split(" ")[-1]
      end
      policy_pftt = policy_rule_map["VSAN.hostFailuresToTolerate"] || "1"
      policy_sftt = policy_rule_map["VSAN.subFailuresToTolerate"] || "0"
      policy_csc = policy_rule_map["VSAN.checksumDisabled"] || "false"
    end

    cluster_to_pick = $cluster_name
    if not _is_ds_local_to_cluster(vsan_datastore_name)
      @local = "Remote"
      cluster_to_pick = _get_vsan_cluster_from_datastore(vsan_datastore_name)
    else
      @local = "Local"
    end

    vsan_stats_hash = _get_vsan_disk_stats(cluster_to_pick)
    total_cache_size = vsan_stats_hash["Total_Cache_Size"]
    num_of_dg = vsan_stats_hash["Total number of Disk Groups"]
    num_of_cap = vsan_stats_hash["Total number of Capacity Drives"]
    dedup = vsan_stats_hash["Dedupe Scope"]
    vsan_type = vsan_stats_hash["vSAN type"]

    if vsan_type == "All-Flash"
      total_cache_size = [num_of_dg * 600,total_cache_size].min
    end
    num_dg_p_host = num_of_dg/host_num
    cap_per_dg = num_of_cap/host_num/num_dg_p_host

    file.puts "#{@local} vSAN Datastore Name: #{vsan_datastore_name}\n"
    file.puts "vSAN Type: #{vsan_type}\n"
    file.puts "Number of Hosts: #{host_num}\n"
    file.puts "Disk Groups per Host: #{num_dg_p_host}\n"
    #file.puts "Cache model: 1 \n"
    file.puts "Total Cache Disk Size: #{total_cache_size} GB"
    file.puts "Capacity Disk per Disk Group: #{cap_per_dg}\n"
    se = "Deduplication/Compression"
    if dedup == 1
      se = "Compression Only"
    elsif dedup == 0
      se = "None"
    end
    file.puts "Space Efficiency: #{se}\n"
    file.puts "Fault Tolerance Preference: #{policy_ftm}\n"
    file.puts "Host Primary Fault Tolerance: #{policy_pftt}\n"
    file.puts "Host Secondary Fault Tolerance: #{policy_sftt}\n"
    file.puts "Checksum Disabled: #{policy_csc.capitalize}\n"
    #sum_stats_full[0].each do |stat|
    #  file.puts stat
    #end
    file.puts vsan_datastores[vsan_datastore_name].transform_keys(&:capitalize).transform_values{|v| if v.instance_of? String; v + " GB" ;else v.to_s.capitalize ;end}.to_yaml
    file.puts "============================================="
  end
  file.puts "Cluster Hosts Map\n"
  file.puts _get_cluster_hosts_map.to_yaml
  file.close()
end
