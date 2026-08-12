# frozen_string_literal: true
module Magentic
  module Runtime
    module Git
      # Local code mutations. The MUTABLE artifacts (flows, run outputs, generated
      # components) get their history from git here; the IMMUTABLE governed artifacts
      # need no history (the SHA is the version). Best-effort, never-raise.
      module Workspace
        module_function
        def snapshot!(dir, message)
          return { ok: false, reason: :not_a_repo } unless system("git -C #{esc(dir)} rev-parse --git-dir > /dev/null 2>&1")
          system("git -C #{esc(dir)} add -A > /dev/null 2>&1")
          ok = system(%(git -C #{esc(dir)} commit -q -m #{esc(message)} > /dev/null 2>&1))
          { ok: !!ok }
        rescue StandardError => e
          { ok: false, reason: :git_error, because: e.message }
        end
        def esc(s) = "'" + s.to_s.gsub("'", %q('\\''))+ "'"
      end
    end
  end
end
