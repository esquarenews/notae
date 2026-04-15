Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(/\Achrome-extension:\/\/[a-p]{32}\z/)

    resource "/api/v1/*",
             headers: %w[Authorization Content-Type Accept X-API-Token],
             methods: %i[get post patch put delete options head],
             expose: %w[Content-Type],
             max_age: 600
  end
end
