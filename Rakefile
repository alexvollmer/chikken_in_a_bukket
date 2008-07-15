# -*- ruby -*-

require 'rubygems'
require 'hoe'
require './lib/chikken_in_a_bukket.rb'

Hoe.new('chikkenbukket', ChikkenInaBukket::VERSION) do |p|
  p.rubyforge_name = 'chikkenbukket'
  p.description = 'Lightweight browser access to your Amazon S3 account';
  p.summary = 'Simple browser access to S3'
  p.url = 'http://chikkenbukket.rubyforge.org'
  p.author = 'Alex Vollmer'
  p.email = 'alex.vollmer@gmail.com'
  p.changes = p.paragraphs_of('History.txt', 0..1).join("\n\n")
  p.extra_deps = [['s33r', '>= 0.5.2'], ['actionpack', '>= 1.13.2'], ['camping', '>= 1.5']]
end

# vim: syntax=Ruby
