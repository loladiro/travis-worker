require 'winrm'

module Travis
  class Worker
    module Shell
      # Encapsulates an SSH connection to a remote host.
      module WinRMHelper
      attr_reader :name, :config, :shell_id, :open, :endpoint

      # Initialize a shell Session
      #
      # config - A hash containing the timeouts, shell buffer time and ssh connection information
      # block - An optional block of commands to be excuted within the session. If
      #         a block is provided then the session will be started, block evaluated,
      #         and then the session will be closed.
      def initialize(name, config)
        @name = name
        @config = Hashr.new(config)
        @shell_id = nil

        if block_given?
          connect
          yield(self) if block_given?
          close
        end
      end

      # Connects to the remote host.
      #
      # Returns the Net::SSH::Shell
      def connect(silent = false)
        info "Starting WinRM session to #{config.host}:#{config.port} ..." unless silent
        @endpoint = WinRM::WinRMWebService.new("http://localhost:5985/wsman", :plaintext, :user => 'vagrant', :pass => 'vagrant', :basic_auth_only => true)
        endpoint.set_timeout(1800)
        @shell_id = endpoint.open_shell
        exec_cmd("powershell",["-encodedCommand",encode_powershell("set-item WSMan:\\localhost\\Client\\allowunencrypted \$true")]) do |stdout,stderr|
        if stdout
            info "Session Out: "+stdout
        end
        if stderr
            info "Session Err: "+stderr
        end
        end
        exec_cmd("powershell",["-encodedCommand",encode_powershell("New-PSSession -ComputerName . -Name Travis -Authentication Basic -Credential (New-Object System.Management.Automation.PSCredential -ArgumentList \"vagrant\",(ConvertTo-SecureString -String \"vagrant\" -AsPlainText -Force))\n Disconnect-PSSession -Name Travis")
]) do |stdout,stderr|
            if stdout
                info "Session Out: "+stdout
            end
            if stderr
                info "Session Err: "+stderr
            end
        end
      end

      # Closes the Shell, flushes and resets the buffer
      def close
        info "Closing Session"
        command = "Connect-PSSession -Name Travis -ComputerName . -Authentication Basic -Credential (New-Object System.Management.Automation.PSCredential -ArgumentList \"vagrant\",(ConvertTo-SecureString -String \"vagrant\" -AsPlainText -Force))\n
                   Remove-PSSession -Name Travis"
        exec_cmd("powershell",["-encodedCommand",encode_powershell(command)]) do |stdout,stderr|
          if stdout
              info "Session Out: "+stdout
          end
          if stderr
              info "Session Err: "+stderr
          end
        end
        info "PSSession Removed"
        endpoint.close_shell shell_id
        buffer.flush
        buffer.reset
      end

      # Allows you to set a callback when output is received from the ssh shell.
      #
      # on_output - The block to be called.
      def on_output(&on_output)
        uuid = Travis.uuid
        @on_output = lambda do |*args, &block|
          Travis.uuid = uuid
          on_output.call(*args, &block)
        end
      end

      # Checks is the current shell is open.
      #
      # Returns true if the shell has been setup and is open, otherwise false.
      def open?
        shell_id != nil
      end

      protected

        # Internal: Sets up and returns a buffer to use for the entire ssh session when code
        # is executed.
        def buffer
          @buffer ||= Buffer.new(config.buffer) do |string|
            @on_output.call(string, :header => log_header) if @on_output
          end
        end

        # Internal: Executes a command using the SSH Shell.
        #
        # This is where the real SSH shell work is done. The command is run along with
        # callbacks setup for when data is returned. The exit status is also captured
        # when the command has finished running.
        #
        # command - The command to be executed.
        # block   - A block which will be called when output or error output is received
        #           from the shell command.
        #
        # Returns the exit status (0 or 1)
      end
    end
  end
end
