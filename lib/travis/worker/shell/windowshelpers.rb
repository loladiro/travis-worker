require 'shellwords'
require 'timeout'
require 'filtered_string'

module Travis
  class Worker
    module Shell
      module WindowsHelpers
        def chdir(dir)
          dir = dir.gsub("/","\\")
          execute("if(!(Test-Path #{dir})) {mkdir #{dir} | out-null} ", :echo => false)
          execute("cd #{dir}")
          execute("[System.IO.Directory]::SetCurrentDirectory($PWD)")
        end

        def cwd
            evaulate_cmd("echo %cd%")
        end

        def file_exists?(filename)
            execute("Test-Path #{filename}", :echo => false)
        end

        def directory_exists?(dirname)
            execute("Test-Path #{dirname}", :echo => false)
        end

        # Executes a command within the ssh shell, returning true or false depending
        # if the command succeded.
        #
        # command - The command to be executed.
        # options - Optional Hash options (default: {}):
        #           :stage - The command stage, used to evaluate the timeout.
        #           :echo  - true or false if the command should be echod to the log
        #
        # Returns true if the command completed successfully, false if it failed.
        def execute(command, options = {}, &block)
          with_timeout(command, options[:stage]) do
            command = echoize(command, &block) unless options[:echo] == false
            exec(_unfiltered(command)) { |p, data| buffer << data if data != nil } == 0
          end
        end

        def execute_cmd(command, options = {}, &block)
          with_timeout(command, options[:stage]) do
            command = echoize_cmd(command, &block) unless options[:echo] == false
            exec_cmd(_unfiltered(command)) { |p, data| buffer << data if data != nil } == 0
          end
        end

        # Evaluates a command within the ssh shell, returning the command output.
        #
        # command - The command to be evaluated.
        # options - Optional Hash options (default: {}):
        #           :echo - true or false if the command should be echod to the log
        #
        # Returns the output from the command.
        # Raises RuntimeError if the commands exit status is 1
        def evaluate(command, options = {})
          result = ''
          command = echoize(command) if options[:echo]
          status = exec(command) do |p, data|
            result << data
            buffer << data if options[:echo]
          end
          raise("command '#{command}' failed: '#{result}'") unless status == 0
          result
        end

        def evaluate_cmd(command, options = {})
          result = ''
          command = echoize_cmd(command) if options[:echo]
          status = exec_cmd(command) do |p, data|
            result << data
            buffer << data if options[:echo]
          end
          raise("command '#{command}' failed: '#{result}'") unless status == 0
          result
        end

        def echo(output, options = {})
          options[:force] ? buffer.send(:concat, output) : buffer << output
        end

        def terminate(message)
          execute_cmd("shutdown /s /t 1 /c \"#{message}\" /f /d p:4:1")
        end

        # Formats a shell command to be echod and executed by a ssh session.
        #
        # cmd - command to format.
        #
        # Returns the cmd formatted.
        def echoize_cmd(cmd, options = {})
          commands = [cmd].flatten.map { |cmd| cmd.respond_to?(:split) ? cmd.split("\n") : cmd }
          commands.flatten.map do |cmd|
            echo = block_given? ? yield(cmd) : cmd
            echo = encode_powershell("Write-Host \"$ "+echo.gsub("\"","`\"")+"\"")
            "powershell -encodedCommand #{echo}\n#{_unfiltered(cmd)}"
          end.join("\n")
        end

        def echoize(cmd, options = {})
          commands = [cmd].flatten.map { |cmd| cmd.respond_to?(:split) ? cmd.split("\n") : cmd }
          commands.flatten.map do |cmd|
            echo = block_given? ? yield(cmd) : cmd
            echo = echo.gsub("\"","`\"")
            "Write-Host \"$ #{echo}\"\n#{_unfiltered(cmd)}"
          end.join("\n")
        end

        # Formats a shell command to be echod and executed by a ssh session.
        #
        # cmd - command to format.
        #
        # Returns the cmd formatted.
        def parse_cmd(cmd)
          cmd.match(/^(\S+=\S+ )*(.*)/).to_a[1..-1].map { |token| token.strip if token }
        end

        def with_timeout(command, stage, &block)
          seconds = timeout(stage)
          begin
            Timeout.timeout(seconds, &block)
          rescue Timeout::Error => e
            raise Travis::Build::CommandTimeout.new(stage, command, seconds)
          end
        end

        def timeout(stage)
          if stage.is_a?(Numeric)
            stage
          else
            config.timeouts[stage || :default]
          end
        end

        def _unfiltered(str)
          str = str.respond_to?(:unfiltered) ? str.unfiltered : str.to_s
        end
        private :_unfiltered
      end
    end
  end
end
