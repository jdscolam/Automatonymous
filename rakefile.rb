COPYRIGHT = "Copyright 2011 Chris Patterson, All rights reserved."

include FileTest
require 'albacore'

BUILD_NUMBER_BASE = '0.4.2'
PRODUCT = 'Automatonymous'
CLR_TOOLS_VERSION = 'v4.0.30319'
OUTPUT_PATH = 'bin/Release'

REVISION = 0
asm_version = BUILD_NUMBER_BASE + "." + REVISION.to_s

props = {
  :src => File.expand_path("src"),
  :output => File.expand_path("build_output"),
  :artifacts => File.expand_path("build_artifacts"),
  :projects => ["Automatonymous"],
  :lib => File.expand_path("lib")
}

desc "Cleans, compiles, il-merges, unit tests, prepares examples, packages zip"
task :all => [:default, :package]

desc "**Default**, compiles and runs tests"
task :default => [:clean, :compile, :tests, :nuget]

desc "Update the common version information for the build. You can call this task without building."
assemblyinfo :global_version do |asm|
  commit_data = get_commit_hash_and_date
  commit = commit_data[0]
  commit_date = commit_data[1]
  build_number = "#{BUILD_NUMBER_BASE}.#{Date.today.strftime('%y%j')}"
  tc_build_number = ENV["BUILD_NUMBER"]
  build_number = "#{BUILD_NUMBER_BASE}.#{tc_build_number}" unless tc_build_number.nil?

  # Assembly file config
  asm.product_name = PRODUCT
  asm.description = "Automatonymous is an open source state machine library."
  asm.version = asm_version
  asm.file_version = build_number
  asm.custom_attributes :AssemblyInformationalVersion => "#{asm_version}",
	:ComVisibleAttribute => false,
	:CLSCompliantAttribute => true
  asm.copyright = COPYRIGHT
  asm.output_file = 'src/SolutionVersion.cs'
  asm.namespaces "System", "System.Reflection", "System.Runtime.InteropServices", "System.Security"
end

desc "Prepares the working directory for a new build"
task :clean do
	FileUtils.rm_rf props[:output]
	waitfor { !exists?(props[:output]) }

	FileUtils.rm_rf props[:artifacts]
	waitfor { !exists?(props[:artifacts]) }

	Dir.mkdir props[:output]
	Dir.mkdir props[:artifacts]
end

desc "Cleans, versions, compiles the application and generates build_output/."
task :compile => [:global_version, :build] do
	copyOutputFiles File.join(props[:src], "Automatonymous/bin/Release"), "Automatonymous.{dll,pdb,xml}", File.join(props[:output], 'net-4.0')
	copyOutputFiles File.join(props[:src], "MassTransit/Automatonymous.MassTransitIntegration/bin/Release"), "Automatonymous.MassTransitIntegration.{dll,pdb,xml}", File.join(props[:output], 'net-4.0')
end

desc "Only compiles the application."
msbuild :build do |msb|
	msb.properties :Configuration => "Release",
		:Platform => 'Any CPU'
	msb.use :net4
	msb.targets :Clean, :Build
	msb.solution = 'src/Automatonymous.sln'
end

def copyOutputFiles(fromDir, filePattern, outDir)
	FileUtils.mkdir_p outDir unless exists?(outDir)
	Dir.glob(File.join(fromDir, filePattern)){|file|
		copy(file, outDir) if File.file?(file)
	}
end

desc "Runs unit tests"
nunit :tests => [:compile] do |nunit|

          nunit.command = File.join('src', 'packages','NUnit.2.5.10.11092', 'tools', 'nunit-console.exe')
          nunit.options = "/framework=#{CLR_TOOLS_VERSION}", '/nothread', '/nologo', '/labels', "\"/xml=#{File.join(props[:artifacts], 'nunit-test-results.xml')}\""
          nunit.assemblies = FileList["tests/Automatonymous.Tests.dll"]
end

task :package => [:nuget]

desc "ZIPs up the build results."
zip :zip_output do |zip|
	zip.directories_to_zip = [props[:stage]]
	zip.output_file = "Automatonymous-#{BUILD_NUMBER_BASE}.zip"
	zip.output_path = [props[:artifacts]]
end

desc "Builds the nuget package"
task :nuget => ['create_nuspec', 'create_nuspec_masstransit'] do
	sh "lib/nuget pack #{props[:artifacts]}/Automatonymous.nuspec /OutputDirectory #{props[:artifacts]}"
	sh "lib/nuget pack #{props[:artifacts]}/Automatonymous.MassTransit.nuspec /OutputDirectory #{props[:artifacts]}"
end

nuspec :create_nuspec do |nuspec|
  nuspec.id = 'Automatonymous'
  nuspec.version = asm_version
  nuspec.authors = 'Chris Patterson'
  nuspec.description = 'Automatonymous is a state machine library for .NET'
  nuspec.title = 'Automatonymous'
  nuspec.projectUrl = 'http://github.com/MassTransit/Automatonymous'
  nuspec.language = "en-US"
  nuspec.licenseUrl = "http://www.apache.org/licenses/LICENSE-2.0"
  nuspec.requireLicenseAcceptance = "true"
  nuspec.output_file = File.join(props[:artifacts], 'Automatonymous.nuspec')
  add_files props[:output], 'Automatonymous.{dll,pdb,xml}', nuspec
end

nuspec :create_nuspec_masstransit do |nuspec|
  nuspec.id = 'Automatonymous.MassTransit'
  nuspec.version = asm_version
  nuspec.authors = 'Chris Patterson'
  nuspec.description = 'Integration assembly to support Automatonymous sagas, a state machine library for .NET'
  nuspec.title = 'Automatonymous.MassTransit'
  nuspec.projectUrl = 'http://github.com/MassTransit/Automatonymous'
  nuspec.language = "en-US"
  nuspec.licenseUrl = "http://www.apache.org/licenses/LICENSE-2.0"
  nuspec.requireLicenseAcceptance = "true"
  nuspec.dependency "MassTransit", "2.1.1.0"
  nuspec.dependency "Automatonymous", asm_version
  nuspec.output_file = File.join(props[:artifacts], 'Automatonymous.MassTransit.nuspec')
  add_files props[:output], 'Automatonymous.MassTransitIntegration.{dll,pdb,xml}', nuspec
end

def project_outputs(props)
	props[:projects].map{ |p| "src/#{p}/bin/#{BUILD_CONFIG}/#{p}.dll" }.
		concat( props[:projects].map{ |p| "src/#{p}/bin/#{BUILD_CONFIG}/#{p}.exe" } ).
		find_all{ |path| exists?(path) }
end

def get_commit_hash_and_date
	begin
		commit = `git log -1 --pretty=format:%H`
		git_date = `git log -1 --date=iso --pretty=format:%ad`
		commit_date = DateTime.parse( git_date ).strftime("%Y-%m-%d %H%M%S")
	rescue
		commit = "git unavailable"
	end

	[commit, commit_date]
end

def add_files stage, what_dlls, nuspec
  [['net40', 'net-4.0']].each{|fw|
    takeFrom = File.join(stage, fw[1], what_dlls)
    Dir.glob(takeFrom).each do |f|
      nuspec.file(f.gsub("/", "\\"), "lib\\#{fw[0]}")
    end
  }
end

def waitfor(&block)
	checks = 0

	until block.call || checks >10
		sleep 0.5
		checks += 1
	end

	raise 'Waitfor timeout expired. Make sure that you aren\'t running something from the build output folders, or that you have browsed to it through Explorer.' if checks > 10
end
