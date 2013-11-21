#
# Author:: Joshua Timberman (<jtimberman@opscode.com>)
# Author:: Graeme Mathieson (<mathie@woss.name>)
# Cookbook Name:: homebrew
# Libraries:: homebrew_package
#
# Copyright 2011-2013, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# cookbook libraries are unconditionally included if the cookbook is
# present on a node. This approach should avoid creating this class if
# the node already has Chef::Provider::Package::Homebrew, such as with
# Chef 12.
# https://github.com/opscode/chef-rfc/blob/master/rfc016-homebrew-osx-package-provider.md
unless defined?(Chef::Provider::Package::Homebrew) && Chef::Platform.find('mac_os_x', nil)[:package] == Chef::Provider::Package::Homebrew
  require 'chef/provider/package'
  require 'chef/resource/package'
  require 'chef/platform'
  require 'chef/mixin/shell_out'

  class Chef
    class Provider
      class Package
        class Homebrew < Package

          include Chef::Mixin::ShellOut
          include ::Homebrew::Mixin

          def load_current_resource
            @current_resource = Chef::Resource::Package.new(@new_resource.name)
            @current_resource.package_name(@new_resource.package_name)
            @current_resource.version(current_installed_version)

            @current_resource
          end

          def install_package(name, version)
            brew('install', @new_resource.options, name, version_arg(version))
          end

          def upgrade_package(name, version)
            brew('upgrade', name, version_arg(version))
          end

          def remove_package(name, version)
            brew('uninstall', @new_resource.options, name, version_arg(version))
          end

          # Homebrew doesn't really have a notion of purging, so just remove.
          def purge_package(name, version)
            @new_resource.options = ((@new_resource.options || '') << ' --force').strip
            remove_package(name, version)
          end

          protected

          def version_arg(version)
            version.to_s.start_with?('-') ? version : '-v=#{version}'
          end

          def brew(*args)
            get_response_from_command('brew #{args.join(' ')}')
          end

          def current_installed_version
            pkg = get_version_from_formula
            versions = pkg.to_hash['installed'].map {|v| v['version']}
            versions.join(' ') unless versions.empty?
          end

          def candidate_version
            pkg = get_version_from_formula
            pkg.stable ? pkg.stable.version.to_s : pkg.version.to_s
          end

          def get_version_from_command(command)
            version = get_response_from_command(command).chomp
            version.empty? ? nil : version
          end

          def brew_library_path
            ::File.join(shell_out!('brew --prefix', :user => homebrew_owner).stdout.chomp, 'Library')
          end

          def get_version_from_formula
            libpath = ::File.join(brew_library_path, 'Homebrew')
            $:.unshift(libpath)

            require 'global'
            require 'cmd/info'

            Formula.factory resolved_package_name
          end

          def resolved_package_name
            package_name = new_resource.package_name

            # Resolves a strange issue on OSX 10.9 and Chef's Omnibus installer's embedded
            # Ruby (1.9.3) where it's unable to resolve symlinks with either Pathname or File
            if Formula.aliases.include? package_name
              alias_path = ::File.join(brew_library_path, 'Aliases', package_name)
              formula_path = ::File.expand_path(::File.readlink(alias_path), ::File.dirname(alias_path))
              formula_name = ::File.basename(formula_path, '.rb')

              Chef::Log.debug 'Resolved alias \'#{package_name}\' to formula \'#{formula_name}\''
              return formula_name
            end

            # When it's resolved the Formula#canonical_name method
            # should be able to resolve aliases as well
            Formula.canonical_name package_name
          end

          def get_response_from_command(command)
            require 'etc'
            home_dir = Etc.getpwnam(homebrew_owner).dir

            Chef::Log.debug 'Executing \'#{command}\' as #{homebrew_owner}'
            output = shell_out!(command, :user => homebrew_owner, :environment => {'HOME' => home_dir})
            output.stdout
          end
        end
      end
    end
  end

  Chef::Platform.set :platform => :mac_os_x_server, :resource => :package, :provider => Chef::Provider::Package::Homebrew
  Chef::Platform.set :platform => :mac_os_x, :resource => :package, :provider => Chef::Provider::Package::Homebrew
end
