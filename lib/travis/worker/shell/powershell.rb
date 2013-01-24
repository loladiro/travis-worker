require 'winrm'

module Travis
  class Worker
    module Shell
      # Encapsulates an SSH connection to a remote host.
      class Powershell
        include Shell::WindowsHelpers
        include Shell::WinRMHelper
        include Logging

        log_header { "#{name}:shell:winrm" }


        def export(name, value, options = nil)
          return unless name
            with_timeout("SET #{name}=#{value}", 3) do
              execute_cmd(*["SET #{name}=#{value}", options].compact)
            end
        end

        def export_line(line, options = nil)
          return unless line

          if line =~ /^TRAVIS_/
            options ||= {}
            options[:echo] = false
          end

          secure = line.sub!(/^SECURE /, '')
          filtered = if secure
            ::Travis::Helpers.obfuscate_env_vars(line)
          else
            line
          end

          line = FilteredString.new(line, filtered)
          line = line.mutate("SET %s", line)
          line = line.to_s unless secure

          with_timeout(line, 3) do
            execute_cmd(*[line, options].compact)
          end
        end

          def exec_cmd(command, arguments = [], &on_output)
            info command
            command_id =  endpoint.run_command(shell_id, command, arguments)
            command_output = endpoint.get_command_output(shell_id, command_id) do |stdout, stderr|
            if stdout
                info stdout
                on_output.call(nil,stdout)
            elsif stderr
                info stderr
                on_output.call(nil,stderr)
            end
            end
            endpoint.cleanup_command(shell_id, command_id)
            command_output[:exitcode]
          end

          def encode_powershell(script)
          script = script.chars.to_a.join("\x00").chomp
          script << "\x00" unless script[-1].eql? "\x00"
          if(defined?(script.encode))
            script = script.encode('ASCII-8BIT')
            script = Base64.strict_encode64(script)
          else
            script = Base64.encode64(script).chomp
          end

          end


          def exec(script, &on_output)
          info script
          command = "$s = Get-PSSession -Name Travis -ComputerName . -Authentication Basic -Credential (New-Object System.Management.Automation.PSCredential -ArgumentList \"vagrant\",(ConvertTo-SecureString -String \"vagrant\" -AsPlainText -Force))\n
          Connect-PSSession -Session $s | out-null\n
          Invoke-Command -Session $s -ScriptBlock {\n
          $encoded = \""+encode_powershell(script+"")+"\"\n
          $bytes = [Convert]::FromBase64String($encoded)\n
          $command = [Text.Encoding]::Unicode.GetString($bytes)\n
          Invoke-Expression $command } 2>&1 | foreach-object {$_.ToString()}\n
          $exitcode = Invoke-Command -Session $s -ScriptBlock { $lastexitcode } \n
          Disconnect-PSSession -Session $s | out-null\n
          exit $exitcode"
          exec_cmd("powershell",["-encodedCommand",encode_powershell(command)], &on_output)
          end


      end
    end
  end
end
