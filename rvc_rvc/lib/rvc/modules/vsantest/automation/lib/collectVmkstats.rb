#!/usr/bin/ruby
require_relative "util.rb"
require_relative "rvc-util.rb"

@dest_folder = "#{ARGV[0]}/vmkstats"

@post_process = ARGV[1]
if @post_process == "true"
  `mkdir -p #{@dest_folder}`
end

@hosts_list = []
@vsan_clusters = _get_all_vsan_clusters
if not @vsan_clusters.empty?
  @vsan_clusters.each do |vsan_cluster|
    @hosts_list = @hosts_list | _get_hosts_list(vsan_cluster)
  end
else
  puts "vSAN not enabled!",@collect_vmkstats_log
  exit(255)
end

@start_collect_vmkstats = 'sh /tmp/vmkstatsCollect.sh > /tmp/vmkstatsCollect.log 2>&1'
@collect_vmkstats_script = "/opt/automation/lib/vmkstatsCollect.sh"
@collect_vmkstats_log = "#{$log_path}/vmkstatsCollect.log"
@failure = false

def run_cmd(host)
  `sed -i '/#{host} /d' /root/.ssh/known_hosts`
  if ssh_valid(host, $host_username, $host_password)
    puts "Uploading collection script to #{host}",@collect_vmkstats_log
    scp_item(host,$host_username,$host_password, @collect_vmkstats_script,"/tmp")
    puts "Start collecting vmkstats on #{host}", @collect_vmkstats_log
    ssh_cmd(host,$host_username,$host_password,@start_collect_vmkstats)
    puts "Finished vmkstats collection on #{host}", @collect_vmkstats_log
    download_item(host, $host_username,$host_password,"/tmp/vmkstatsCollect.log", "#{$log_path}/#{host}-vmkstatsCollect.log")
  else
    puts "Unable to SSH to #{host}",@collect_vmkstats_log
    @failure = true
  end
end

def post_process(host)
  `sed -i '/#{host} /d' /root/.ssh/known_hosts`
  if ssh_valid(host, $host_username, $host_password)
    download_item(host, $host_username,$host_password,"/tmp/hcibench_vmkstats_dumpDir/.", "#{@dest_folder}/#{host}-vmkstats/",{:recursive => true})
    `/opt/automation/lib/vmkstats_postprocess.sh #{@dest_folder}/#{host}-vmkstats /opt/automation/lib/vmcallstackview.jar`
  else
    puts "Unable to SSH to #{host}",@collect_vmkstats_log
    @failure = true
  end
end

tnode = []
@hosts_list.each do |s|
  if @post_process == "true"
    tnode << Thread.new{post_process(s)}
  else
    tnode << Thread.new{run_cmd(s)}
  end
end
tnode.each{|t|t.join}

if @failure
  exit(250)
else
  exit
end