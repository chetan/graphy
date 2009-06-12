#!/usr/bin/env ruby

# == Synopsis 
#   This is a sample description of the application.
#   Blah blah blah.
#
# == Examples
#   This command does blah blah blah.
#     graphweb.rb --file data/test
#
# == Usage 
#   graphweb.rb [options] --file [DATA.CSV]
#
#   For help use: graphweb.rb --help
#
# == Options
#   -h, --help          Displays help message
#   -V, --version       Display the version, then exit
#   -q, --quiet         Output as little as possible, overrides verbose
#   -v, --verbose       Verbose output
#   -f, --file [FILE]   CSV file containing data
#
# == Author
#   Chetan Sarva <chetan@pixelcop.net>
#
# == Copyright
#   Copyright (c) 2009 Chetan Sarva. Licensed under the MIT License:
#   http://www.opensource.org/licenses/mit-license.php


# TODO
# configurable columns
#   date and time in any column
#   date and time in different formats 
#   data from any column
# labels for columns to go in output
# input from stdin
# use out:csv instead of rendering in html source
# simple form for controlling out:csv query - range? etc
# detect header row in csv file

# DONE
# rollup each interval (take an average of values instead of dropping) aka rolling/moving average
# multiple datasets (multiple columns with data)
# "primary" dataset for applying std dev
# command line options
# pass filename for input

require 'optparse' 
require 'rdoc/usage'
require 'ostruct'
require 'date'
require 'pp'
require 'webrick'
include WEBrick

def stopwatch(print_time = false)
    start_time = Time.new
    yield
    return if not print_time
    puts "took %s seconds" % (Time.new - start_time)
end

class DataServlet < HTTPServlet::AbstractServlet

    def do_GET(req, res)
    
#        puts "ajax data request"
    
        dataset = DataSet.create
        res.body = dataset.to_js_table()
    
    end

end

class GraphServlet < HTTPServlet::AbstractServlet

    def do_GET(req, res)
  
        res['Content-Type'] = 'text/html'
        
        datasets = DataSet.create
        
        body = []
        body << <<-EOF
<html>
  <head>
    <link rel="stylesheet" media="screen" href="/files/css/graphy.css">
    <script type='text/javascript' src='http://www.google.com/jsapi'></script>
    <script type='text/javascript' src='/files/js/jquery-1.3.2.min.js'></script>
    <script type='text/javascript'>
      google.load('visualization', '1', {'packages':['annotatedtimeline']});
      google.setOnLoadCallback(drawChart);
      function drawChart() {
        var i;
        var data_table = new google.visualization.DataTable(
EOF
        body << datasets.to_js_table()
        body << ", 0.5);\n\n"

        body << <<-EOF
        var chart = new google.visualization.AnnotatedTimeLine(document.getElementById('chart_div'));
        chart.draw(data_table, {displayAnnotations: true});
        
        $("#cli").keypress(function(k) { 
            if (k.which != 13) {
                return;
            }
            
            $.ajax({
                url: "/eval",
                global: false,
                type: "POST",
                data: ({code : $("#cli").val()}),
                dataType: "html",
                success: function(msg) {
                    // add msg to scrollback buffer
                    result = "<b>" + msg + "</b><br/>"
                    iframe_body.prepend(result);

                    refresh_chart_data();
                    
                }
            });
            
        });
        
        function refresh_chart_data() {
            $.ajax({
                url: "/data",
                global: false,
                type: "GET",
                dataType: "html",
                success: function(msg) {
                    // text is input for new chart
                    dt_cmd = "new google.visualization.DataTable(" + msg + ", 0.5);";
                    data_table = eval(dt_cmd);
                    //input_data = eval(msg);
                    //data_table = new google.visualization.DataTable(msg, 0.5);
                    chart.draw(data_table, {displayAnnotations: true});
                }
            });        
        }
        
        var iframe_body;
        
        $(document).ready(function() {
            iframe_body = $('body', $('iframe')[0].contentWindow.document);
            iframe_body.css('font-family', $('iframe').css('font-family'));        
        });
        
      }
    </script>
  </head>

  <body>
    <div id='chart_div' style='width: 98%; height: 240px;'></div>
    
    <div id="console">
      <input type="text" id="cli" />
    </div>
    <div id="buffer"><iframe id="scrollback"></iframe></div>
  </body>
</html>
EOF
    
        res.body = body.join
    
    end
       
end

class EvalServlet < HTTPServlet::AbstractServlet

    def do_GET(req, res)
        do_POST(req, res)
    end

    def do_POST(req, res)
    
        code = req.query['code'].strip
        i = code.index(' ')
        if i.nil? then
            cmd = code
            args = nil
        else
            cmd = code[0, i].strip
            args = code[i, code.length].strip
        end
        
        puts "got cmd: %s" % cmd
        puts "got args: %s" % args
        
        stack = DataStack.create
        
        case cmd    
        when "pop" 
#            puts "popping"
            stack.pop
        else
#            puts "pushing command?"
            if GraphyMath.method_defined? cmd then
#                puts "yes!"
                lib = GraphyMath::Lib.new
                op = lib.method(cmd)
                proc_cmd = "Proc.new { |data| op.call(data"
                if args.nil? or args.empty? then
                    proc_cmd += ") }"
                else
                    proc_cmd += (", %s) }" % args)
                end
                puts "new op: " + proc_cmd
                proc = eval(proc_cmd)
                stack << proc
            end
        end
        
        res.body = "> " + code + "<br/>"
        res.body += "ok."
            
#         
#         begin
#             ret = eval(code)
#         rescue => ex
#             res.body = "> " + code + "<br/>not ok. " + ex
#             return
#         end
#         
#         res.body = "> " + code + "<br/>"
#         if ret.nil? or not ret then
#             res.body += "ok."
#         else
#             res.body += ("%s" % ret)
#         end
        
    end
    
end

class DataStack
    
    attr_accessor :ops

    private_class_method :new
    @@stack = nil
    def self.create
        @@stack = new if not @@stack
        return @@stack
    end
    
    def initialize
        @ops = []
    end
    
    def <<(op)
        ops << op
        dataset = DataSet.create
        dataset.data = op.call(dataset.data)
    end
    
    def pop
#        puts "popping"
        ops.pop
        process
    end
    
    def process
#        puts "processing"
        dataset = DataSet.create
        dataset.reset
        return if ops.empty?
        ops.each { |op|
#            puts "processing an op.."
            dataset.data = op.call(dataset.data)
        }
        puts "done processing"
    end
    
end

# need this singleton so we can grab the data from inside our servlet
class DataSet
    
    attr_accessor :data, :num, :cols, :orig_data

    private_class_method :new
    @@dataset = nil
    def self.create
        @@dataset = new if not @@dataset
        return @@dataset
    end
    
    def initialize
        @orig_data = []
        @data = []
        @cols = []
        @num = 0
    end
    
    def set_data(data)
        @orig_data = @data = data
    end
    
    def reset
#        puts "resetting dataset"
        @data = @orig_data
    end
    
    
#     {
#       cols: [{id: 'A', label: 'NEW A', type: 'string'},
#              {id: 'B', label: 'B-label', type: 'number'},
#              {id: 'C', label: 'C-label', type: 'date'}
#             ],
#       rows: [{c:[{v: 'a'}, {v: 1.0, f: 'One'}, {v: new Date(2008, 1, 28, 0, 31, 26), f: '2/28/08 12:31 AM'}]},
#              {c:[{v: 'b'}, {v: 2.0, f: 'Two'}, {v: new Date(2008, 2, 30, 0, 31, 26), f: '3/30/08 12:31 AM'}]},
#              {c:[{v: 'c'}, {v: 3.0, f: 'Three'}, {v: new Date(2008, 3, 30, 0, 31, 26), f: '4/30/08 12:31 AM'}]}
#             ]
#     }  
    
    def to_js_table
    
#        puts "to_js_table"
    
        buff = []
        
        buff << '{ '
        buff << 'cols: ['
        buff << "{id: 'date', label: 'Date/Time', type: 'datetime'}"
        @cols.each_with_index { |col,i|
            buff << ",{id: 'col_#{i}', label: '#{col}', type: 'number'}"
        }
        buff << "],"
        
        buff << 'rows: ['
        
        if @data.length > 10000 then
            # TODO too large! return an empty set for now
            buff << '] }'
            return buff.join
        end
        
        @data.each_with_index { |d,i|
            buff << "," if i > 0
            buff << sprintf("{c:[{v: new Date(%s)}", d[0] * 1000)
            (1..@num).each { |idx|
                buff << sprintf(",{v: %s}", d[idx])
            }
            buff << "]}"
        }
        buff << "] }"
        
        return buff.join
    
    end
    
    def to_csv
    
        buff = []
        
        buff << 'date'
        @cols.each { |col|
            buff << ',' + col[0]
        }
        buff << "\n"
        
        @data.each { |d|
            buff << sprintf("%s", d[0] * 1000)
            (1..@num).each { |idx|
                buff << sprintf(",%s", d[idx])
            }
            buff << "\n"
        }
        
        return buff.join()
    
    end

end

module GraphyMath

    class Lib
        include GraphyMath
    end

# variance & std dev swiped from 
# http://warrenseen.com/blog/2006/03/13/how-to-calculate-standard-deviation/

# calculate the variance of a population
# accepts: an array, the population
# returns: the variance
def variance(population)
    n = 0
    mean = 0.0
    s = 0.0
    population.each { |x|
        n = n + 1
        delta = x - mean
        mean = mean + (delta / n)
        s = s + delta * (x - mean)
    }
    # if you want to calculate std deviation
    # of a sample change this to "s / (n-1)"
    return s / n
end

# calculate the standard deviation of a population
# accepts: an array, the population
# returns: the standard deviation
def standard_deviation(population)
    Math.sqrt(variance(population))
end

def sum(population)
    return 0 if not population or population.empty?
    sum = 0
    population.each { |n| sum += n }
    return sum
end

def average(population) 
    return 0 if not population or population.empty?
    avg = sum(population) / population.length
end

# reduce dataset using intervals
def create_intervals(pop, interval)
    next_line = interval
    intervals = []
    pop.each { |d|
        if d[0] >= next_line then
            next_line = d[0] + interval
            intervals << d
        end
    }
    return intervals
end

# we could make this routine even more generic by not assuming any qualities of pop
# e.g., that in this case it is an array of arrays
# by using procs to do the actual rollups and window testing
def create_rolling_intervals(pop, interval)
    
    w_start = 0
    w_end = interval
    
    intervals = []
    window = []
    
    prc = Proc.new { |d, last|
        if window.length > 0 then
            last_val = window[-1]
            # rollup each data column
            r = [ last_val[0] ]
            (1..DataSet.create.num).each { |idx|
                r << average( window.collect { |n| n[idx] } )
            }
            intervals << r
        else
            last_val = d
        end        
        if not last then
            # start new one
            window = [ d ]
            w_start = last_val[0]
            w_end = last_val[0] + interval
        end
    }
    
    # 1 2 3 4 5 5 5 6 7 8
    pop.each { |d|
        if d[0] >= w_start and d[0] <= w_end then
            # within the current interval window
            window << d
        else
            # we've passed outside of the current interval window
            #   average the last window, and start a new one
            #p d
            prc.call(d, false)
            
        end
    }
    prc.call(nil, true)
    return intervals
end

def remove_outliers(data, pop, index)
    std_dev = standard_deviation(pop)
    outlier = average(pop) + (std_dev * 2)
    return data.delete_if { |d| d[index] >= outlier }
end

# data = our dataset matrix, usually like [timestamp, col1, col2, col3...]
# index = col to act on
# remove_outliers = whether or not to remove points outside 2 std deviations
def massage_data(data, index, remove_outliers = true)

    # remove outliers - anything more than 2 std deviations away
    pop = data.collect { |d| d[index] }
    data = remove_outliers(data, pop, index) if remove_outliers
    
    # when dealing with multiple datasets, will want to change the scale to 0-100
    # for each set so it graphs nicely
    max = pop.max
    data.each { |d| 
        d[index] = d[index]  / max * 100 
    }
    
    return data

end

end # module GraphyMath

class Graphy

    include GraphyMath

    # currently a file stream works best
    def load_data(filename)
    
        print "loading data... "
        STDOUT.flush
        
        stream = File.new(filename)
    
        @datasets = DataSet.create
        
        # setup column info
        # [ ['Page size', 'title1', 'text1'], ['Response time', 'title2', 'text2'] ]
        @datasets.cols = [ ['Page size', '', ''], ['Response time', '', ''] ]
        
        # load csv input
        all_lines = []
        stream.each_line { |line| all_lines << line.strip.split(/[,\t]/).map { |s| s.to_f } }
        if all_lines.length == 0 then
            puts "no data found!"
            exit
        end
        @datasets.num = all_lines[0].length - 1
        
        # sort by date/timestamp (ascending)
        all_lines.sort! { |a,b| a[0] <=> b[0] }
        
        @datasets.set_data(all_lines)
        
        puts "done"
        
        # now use our stacks
        
        print "massaging... "
        STDOUT.flush
        
        stack = DataStack.create
        stack << Proc.new { |data| create_rolling_intervals(data, 60) }
        stack << Proc.new { |data| massage_data(data, 1) }
        stack << Proc.new { |data| massage_data(data, 2) }
        
        puts "done"
        
    end

    def run
        
        puts ''
        puts 'Going to start server at http://localhost:2000/graph'
        puts ''
        
        s = HTTPServer.new( :Port => 2000, :AccessLog => [ ['/dev/null',AccessLog::COMMON_LOG_FORMAT] ],
                                           :Logger    => WEBrick::BasicLog.new("/dev/null"))
        s.mount("/graph", GraphServlet)
        s.mount("/eval", EvalServlet)
        s.mount("/data", DataServlet)
        s.mount("/files", HTTPServlet::FileHandler, File.expand_path(File.dirname(__FILE__)), false)
        trap("INT"){ s.shutdown }
        s.start
    
    end

end

class GraphyCli

    VERSION = '0.1'
    
    attr_reader :options

    def initialize(arguments, stdin)
        @arguments = arguments
        @stdin = stdin
        
        # Set defaults
        @options = OpenStruct.new
        @options.verbose = false
        @options.quiet = false
        
        @graphy = Graphy.new
        
    end

    # Parse options, check arguments, then process the command
    def run
                
        if parsed_options? && arguments_valid? 

            process_arguments
            process_command
            
        else
            output_usage
        end
            
    end
    
    protected
    
    def parsed_options?
        
        # Specify options
        opts = OptionParser.new 
        opts.on('-V', '--version')        { output_version ; exit 0 }
        opts.on('-h', '--help')           { output_help }
        opts.on('-v', '--verbose')        { @options.verbose = true }    
        opts.on('-q', '--quiet')          { @options.quiet = true }
        
        opts.on('-f', '--file [FILE]')           { |f| @options.file = f }
        
                    
        opts.parse!(@arguments) rescue return false
        
        process_options
        true            
    end

    # Performs post-parse processing on options
    def process_options
        @options.verbose = false if @options.quiet
    end
    
    def output_options
        puts "Options:\n"
        
        @options.marshal_dump.each do |name, val|                
            puts "    #{name} = #{val}"
        end
    end

    # True if required arguments were provided
    def arguments_valid?
        if not @options.file then
            return false
        end
        return true
    end
    
    # Setup the arguments
    def process_arguments
        # TO DO - place in local vars, etc
    end
    
    def process_command
        #process_standard_input # [Optional]
        stopwatch(true) {
            @graphy.load_data(@options.file)
        }
        @graphy.run        
        
    end

    def process_standard_input
        input = @stdin.read            
        # TO DO - process input
        
        # [Optional]
        #@stdin.each do |line| 
        #    # TO DO - process each line
        #end
    end
    
    def output_help
        output_version
        RDoc::usage() #exits app
    end
    
    def output_usage
        RDoc::usage('usage') # gets usage from comments above
    end
    
    def output_version
        puts "#{File.basename(__FILE__)} version #{VERSION}"
    end
    
end

# Create and run the application
app = GraphyCli.new(ARGV, STDIN)
app.run
