#!/usr/bin/env ruby

require 'fileutils'
require 'time'
require 'optparse'

# CLI tool name: ghostbsd-ports-sync
# Usage: ghostbsd-ports-sync [--verbose] [--dry-run]

# Configuration
GHOSTBSD_REPO      = 'https://github.com/ghostbsd/ghostbsd-ports.git'
FREEBSD_REPO       = 'https://github.com/freebsd/freebsd-ports.git'
FREEBSD_COMMIT     = 'latest'  # replace with a specific commit hash for reproducibility
WORKING_DIR        = File.expand_path('~/ghostbsd-ports')
BRANCH_NAME        = "sync-freebsd-#{Time.now.strftime('%Y%m%d')}"
POUDRIERE_JAIL     = 'ghostbsd-14_amd64'
POUDRIERE_VERSION  = '14.0-RELEASE'
POUDRIERE_PORTS    = 'ghostbsd-ports'
MERGE_BACKUP_DIR   = File.expand_path("~/ghostbsd-ports-merge-backups")
LOG_FILE           = File.expand_path('~/ghostbsd-ports-sync.log')

ENV['TZ'] = 'UTC'
ENV['LC_ALL'] = 'C'
ENV['LANG'] = 'C'
ENV['SOURCE_DATE_EPOCH'] = '1700000000'  # fixed timestamp for reproducibility

$options = {
  verbose: false,
  dry_run: false
}

OptionParser.new do |opts|
  opts.banner = "Usage: ghostbsd-ports-sync [options]"

  opts.on('-v', '--verbose', 'Enable verbose logging') do
    $options[:verbose] = true
  end

  opts.on('-n', '--dry-run', 'Run without pushing changes or committing') do
    $options[:dry_run] = true
  end

  opts.on('-h', '--help', 'Prints help') do
    puts opts
    exit
  end
end.parse!

# Logging helper
def log(msg, level = :info)
  timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
  prefix = case level
           when :info then "\u2139"
           when :warn then "\u26A0"
           when :error then "\u2718"
           when :success then "\u2714"
           else "\u2022"
           end
  full_msg = "[#{timestamp}] #{prefix} #{msg}"
  puts full_msg if $options[:verbose] || level != :info
  File.open(LOG_FILE, 'a') { |f| f.puts(full_msg) }
end

def run_cmd(cmd, fatal: true, desc: nil)
  log(desc || cmd)
  success = system(cmd)
  unless success
    log("Command failed: #{cmd}", fatal ? :error : :warn)
    exit 1 if fatal
  end
  success
end

def check_git_installed
  unless system('which git > /dev/null')
    log('Git is not installed or not in PATH.', :error)
    exit 1
  end
end

def check_diff3_installed
  unless system('which diff3 > /dev/null')
    log('diff3 is not installed or not in PATH.', :error)
    exit 1
  end
end

def clone_ghostbsd_repo
  unless Dir.exist?(WORKING_DIR)
    log("Cloning GhostBSD ports repo into #{WORKING_DIR}...")
    run_cmd("git clone #{GHOSTBSD_REPO} #{WORKING_DIR}", desc: "Cloning GhostBSD repository")
  else
    log("GhostBSD ports directory already exists, skipping clone.")
  end
end

def setup_freebsd_remote
  Dir.chdir(WORKING_DIR) do
    remotes = `git remote`.split
    unless remotes.include?('freebsd')
      run_cmd("git remote add freebsd #{FREEBSD_REPO}", desc: "Adding FreeBSD as remote")
    else
      log("Remote 'freebsd' already exists, skipping.")
    end
  end
end

def prepare_branch
  Dir.chdir(WORKING_DIR) do
    run_cmd('git checkout master', desc: "Switching to master branch")
    run_cmd('git pull origin master', desc: "Pulling latest changes from origin master")
    run_cmd("git checkout -b #{BRANCH_NAME}", desc: "Creating and switching to new branch #{BRANCH_NAME}")
  end
end

def merge_freebsd
  Dir.chdir(WORKING_DIR) do
    run_cmd('git fetch freebsd', desc: "Fetching FreeBSD repository")
    if FREEBSD_COMMIT != 'latest'
      run_cmd("git merge #{FREEBSD_COMMIT}", desc: "Merging specific FreeBSD commit #{FREEBSD_COMMIT}")
    else
      unless system('git merge freebsd/master')
        log('Merge conflict(s) detected. Attempting diff3 resolution...', :warn)
        resolve_conflicts_with_diff3
        return
      end
    end
    log("Merge completed successfully.", :success)
  end
end

def resolve_conflicts_with_diff3
  Dir.chdir(WORKING_DIR) do
    FileUtils.mkdir_p(MERGE_BACKUP_DIR)
    conflict_files = `git diff --name-only --diff-filter=U`.split

    conflict_files.each do |file|
      log("Resolving conflict: #{file}", :warn)
      begin
        base    = `git show :1:#{file}` rescue ''
        ours    = `git show :2:#{file}` rescue ''
        theirs  = `git show :3:#{file}` rescue ''

        if [base, ours, theirs].any?(&:empty?)
          log("Skipping #{file} — one of the file versions is missing.", :error)
          next
        end

        base_file   = "#{MERGE_BACKUP_DIR}/#{File.basename(file)}.BASE"
        ours_file   = "#{MERGE_BACKUP_DIR}/#{File.basename(file)}.OURS"
        theirs_file = "#{MERGE_BACKUP_DIR}/#{File.basename(file)}.THEIRS"
        output_file = "#{MERGE_BACKUP_DIR}/#{File.basename(file)}.MERGED"

        File.write(base_file, base)
        File.write(ours_file, ours)
        File.write(theirs_file, theirs)

        log("Merging #{file} using diff3...")
        merge_success = system("diff3 -m #{ours_file} #{base_file} #{theirs_file} > #{output_file}")
        unless merge_success
          log("diff3 failed on #{file}", :error)
          next
        end

        if File.read(output_file).include?('<<<<<<')
          log("Conflict markers remain in #{file}. Manual resolution required.", :warn)
          next
        end

        FileUtils.cp(file, "#{MERGE_BACKUP_DIR}/#{File.basename(file)}.ORIGINAL") if File.exist?(file)
        FileUtils.cp(output_file, file)
        run_cmd("git add #{file}", desc: "Staging resolved #{file}")
        log("Auto-resolved #{file} using diff3", :success)
      rescue => e
        log("Exception while resolving #{file}: #{e.message}", :error)
      end
    end

    if `git diff --cached --name-only`.split.any?
      run_cmd("git commit -m 'Auto-resolved merge conflicts using diff3'", desc: "Committing merged files")
    else
      log("No changes staged. Merge may still require manual resolution.", :warn)
    end
  end
end

def poudriere_test
  run_cmd("sudo poudriere jail -c -j #{POUDRIERE_JAIL} -v #{POUDRIERE_VERSION} -a amd64 -m ftp",
          desc: "Ensuring poudriere jail #{POUDRIERE_JAIL} is created")
  run_cmd("sudo poudriere ports -c -p #{POUDRIERE_PORTS} -m git -B main",
          desc: "Ensuring poudriere ports tree #{POUDRIERE_PORTS} is created")
  run_cmd("sudo poudriere bulk -j #{POUDRIERE_JAIL} -p #{POUDRIERE_PORTS} -an",
          desc: "Running poudriere dry-run test")
end

def push_branch
  return log("Dry run enabled, skipping push.", :info) if $options[:dry_run]
  Dir.chdir(WORKING_DIR) do
    run_cmd("git push origin #{BRANCH_NAME}", desc: "Pushing new branch to GitHub")
  end
end

# Main
log("Starting GhostBSD ports sync process...")
check_git_installed
check_diff3_installed
clone_ghostbsd_repo
setup_freebsd_remote
prepare_branch
merge_freebsd
poudriere_test
push_branch
log("Sync process completed. Ready for pull request: #{BRANCH_NAME}", :success)
