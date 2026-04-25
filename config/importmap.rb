# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@rails/actioncable", to: "actioncable.esm.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@tiptap/core", to: "https://esm.sh/@tiptap/core@2.10.4?bundle", preload: false
pin "@tiptap/starter-kit", to: "https://esm.sh/@tiptap/starter-kit@2.10.4?bundle", preload: false
pin "@tiptap/extension-link", to: "https://esm.sh/@tiptap/extension-link@2.10.4?bundle", preload: false
pin "@tiptap/extension-task-list", to: "https://esm.sh/@tiptap/extension-task-list@2.10.4?bundle", preload: false
pin "@tiptap/extension-task-item", to: "https://esm.sh/@tiptap/extension-task-item@2.10.4?bundle", preload: false
pin "three", to: "https://esm.sh/three@0.164.1?bundle", preload: false
pin_all_from "app/javascript/controllers", under: "controllers", preload: false
