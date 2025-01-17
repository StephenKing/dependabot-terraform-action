#!/usr/bin/env ruby
# This script is designed to loop through all dependencies Github
# Terraform project and create according pull requests

require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"
require "dependabot/omnibus"


# Utilize the github env variable per default
repo_name = ENV["GITHUB_REPOSITORY"]
if repo_name.empty?
  print "GITHUB_REPOSITORY needs to be set"
  exit(1)
end

# Directory where the base dependency files are.
directory = ENV["INPUT_DIRECTORY"] || "/"
if directory.empty?
  print "The directory needs to be set"
  exit(1)
end

# Hardcode the package manager to terraform
package_manager = "terraform"

# Define the target branch
target_branch = ENV["INPUT_TARGET_BRANCH"]
if target_branch.empty?
  target_branch=nil
end

# Token to be used for fetching repository files / creating pull requests
repo_token = ENV["INPUT_TOKEN"]
if repo_token.empty?
  print "A github token needs to be provided"
  exit(1)
end

credentials_repository = [
  {
    "type" => "git_source",
    "host" => "github.com",
    "username" => "x-access-token",
    "password" => repo_token
  }
]

credentials_dependencies = []

# Token to be used for fetching dependencies from github
dependency_token = ENV["INPUT_GITHUB_DEPENDENCY_TOKEN"]
unless dependency_token.empty?
  credentials_dependencies.push(
    {
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => dependency_token
    }
  )
end



source = Dependabot::Source.new(
  provider: "github",
  repo: repo_name,
  directory: directory,
  branch: target_branch,
)


##############################
# Fetch the dependency files #
##############################
puts "Fetching #{package_manager} dependency files for #{repo_name}"
fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).new(
  source: source,
  credentials: credentials_repository,
)

files = fetcher.files
commit = fetcher.commit

##############################
# Parse the dependency files #
##############################
puts "Parsing dependencies information"
parser = Dependabot::FileParsers.for_package_manager(package_manager).new(
  dependency_files: files,
  source: source,
  credentials: credentials_repository,
)

dependencies = parser.parse

dependencies.select(&:top_level?).each do |dep|
  #########################################
  # Get update details for the dependency #
  #########################################
  checker = Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
    dependency: dep,
    dependency_files: files,
    credentials: credentials_dependencies,
  )

  next if checker.up_to_date?

  requirements_to_unlock =
    if !checker.requirements_unlocked_or_can_be?
      if checker.can_update?(requirements_to_unlock: :none) then :none
      else :update_not_possible
      end
    elsif checker.can_update?(requirements_to_unlock: :own) then :own
    elsif checker.can_update?(requirements_to_unlock: :all) then :all
    else :update_not_possible
    end

  next if requirements_to_unlock == :update_not_possible

  updated_deps = checker.updated_dependencies(
    requirements_to_unlock: requirements_to_unlock
  )

  #####################################
  # Generate updated dependency files #
  #####################################
  print "  - Updating #{dep.name} (from #{dep.version})…"
  updater = Dependabot::FileUpdaters.for_package_manager(package_manager).new(
    dependencies: updated_deps,
    dependency_files: files,
    credentials: credentials_repository,
  )

  updated_files = updater.updated_dependency_files

  ########################################
  # Create a pull request for the update #
  ########################################
  pr_creator = Dependabot::PullRequestCreator.new(
    source: source,
    base_commit: commit,
    dependencies: updated_deps,
    files: updated_files,
    credentials: credentials_repository,
    label_language: false,
  )
  pull_request = pr_creator.create
  puts " submitted"

  next unless pull_request

end

puts "Done"
