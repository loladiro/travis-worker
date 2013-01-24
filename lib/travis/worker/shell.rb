module Travis
  class Worker
    module Shell
      autoload :Buffer,         'travis/worker/shell/buffer'
      autoload :WindowsHelpers, 'travis/worker/shell/windowshelpers'
      autoload :WinRMHelper,    'travis/worker/shell/winrm'
      autoload :Powershell,     'travis/worker/shell/powershell'
    end
  end
end
