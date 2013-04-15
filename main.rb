# encoding: UTF-8

# TODO: Support percent sign following closing parens and variables
# TODO: Add support for other types of output: like money and percents
# TODO: Add currency conversion
# TODO: Add unit conversion
# TODO: Support adding/subtracting percentages (ex: 10% + 20% = 30%)

require 'quickcalc'

query = ARGV[0]

bundle_id = "com.clintonstrong.QuickCalc"
data_dir = File.expand_path("~/Library/Application Support/Alfred 2/Workflow Data/#{bundle_id}")
custom_file = "#{data_dir}/custom.txt"

Dir::mkdir(data_dir) unless File.exist?(data_dir)

unless File.exist?(custom_file)
  File.open(custom_file, 'w') do |f|
    f.puts('/* Check `man bc` for more info on custom functions')
    f.puts(' * Or: <http://en.wikipedia.org/wiki/Bc_programming_language> */')
  end
end

qc = QuickCalc.new(query, './functions.txt', custom_file)

result = qc.calculate

error_found = result.include?('error')

answer = qc.remove_trailing_zero(result.to_f)

if $?.exitstatus > 0 || error_found
  valid = 'no'
  answer = 0
  formatted_answer = '...'
  subtitle = 'Please enter a valid expression'
else
  valid = 'yes'
  formatted_answer = qc.format_number(answer)
  subtitle = 'Action this item to copy this number to the clipboard'
end

puts <<-eos
  <?xml version='1.0'?>
  <items>
    <item valid='#{valid}' uid='#{answer}' arg='#{answer}'>
      <title>#{formatted_answer}</title>
      <subtitle>#{subtitle}</subtitle>
      <icon type="fileicon">/Applications/Calculator.app</icon>
    </item>
  </items>
eos
