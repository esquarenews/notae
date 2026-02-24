# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@rails/actioncable", to: "actioncable.esm.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@tiptap/core", to: "https://esm.sh/@tiptap/core@2.10.4"
pin "@tiptap/starter-kit", to: "https://esm.sh/@tiptap/starter-kit@2.10.4"
pin_all_from "app/javascript/controllers", under: "controllers"
