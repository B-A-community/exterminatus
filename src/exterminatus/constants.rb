# frozen_string_literal: true

module BACommunity
  module Terminal
    PLUGIN_NAME = 'Exterminatus'
    VERSION     = '0.3.1'

    # Ключ для Sketchup.read_default / write_default и окон HtmlDialog.
    PREFS_KEY = 'BACommunity_Exterminatus'

    # Сколько строк вывода держим в памяти и сколько введённых строк помним
    # между сеансами.
    LOG_LIMIT     = 300
    HISTORY_LIMIT = 200

    # Имена команд, синонимов и параметров — строго латиница: так их можно
    # набирать в любой раскладке и в любой языковой сборке плагина.
    ID_PATTERN   = /\A[A-Z][A-Za-z0-9]*\z/.freeze
    NAME_PATTERN = /\A[A-Za-z][A-Za-z0-9]*\z/.freeze
  end
end
