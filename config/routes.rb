# frozen_string_literal: true

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root 'chats#index'

  # General AI Chat
  resources :chats, only: [:create]
  get '/models', to: 'chats#models'
  post '/chats/stream', to: 'chats#stream'

  # Trading Chat
  get '/trading', to: 'trading#index'
  get '/trading/account', to: 'trading#account_info'
  get '/trading/positions', to: 'trading#positions'
  get '/trading/holdings', to: 'trading#holdings'
  get '/trading/quote', to: 'trading#quote'
  get '/trading/historical', to: 'trading#historical'
  post '/trading/agent', to: 'trading#agent' # AI Agent endpoint
  post '/trading/agent_stream', to: 'trading#agent_stream' # AI Agent streaming endpoint
  post '/trading/technical_analysis_stream', to: 'trading#technical_analysis_stream' # Technical Analysis Agent streaming endpoint

  # DhanHQ Market Data API (reliable wrapper)
  namespace :dhan do
    get 'search_instruments', to: 'market#search_instruments'
    get 'quote', to: 'market#quote'
    get 'ohlc', to: 'market#ohlc'
    get 'historical', to: 'market#historical'
    get 'option_chain', to: 'market#option_chain'
  end

  # Trading Agent (Plan → Act → Observe Loop)
  post '/trading_agent/run', to: 'trading_agent#run'
end
