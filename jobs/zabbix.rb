# coding: utf-8
require "zabbixapi"
require "json"
require 'date'
require 'time'

config_file = File.read(Dir.pwd + '/jobs/zabbix-monitor-config.json')
config_parsed = JSON.parse(config_file)

#Your auth token
auth_token = config_parsed['auth_token']

#Your Zabbix API configuration
# if informer ON - comment
zbx = ZabbixApi.connect(
         :url => config_parsed['Zabbix']['api_config']['url'],
         :user => config_parsed['Zabbix']['api_config']['user'],
         :password => config_parsed['Zabbix']['api_config']['password']
        )

zbx_priorities = {
   0 => "ok",
   1 => "info",
   2 => "warning",
   3 => "average",
   4 => "high",
   5 => "disaster",
   10 => "acknowledged"
}


# :first_in sets how long it takes before the job is first run. In this case, it is run immediately
SCHEDULER.every '1m', :first_in => 0 do |job|                                        #----------------------1-----------------------

  hostgroupids = []
  hostgroup_names = []
  alias_names = []

  ###############################################################
  # informer for changes
  ###############################################################
  #(config_parsed['Zabbix']['aliases']).each do |zabbix_group|
  #             send_event(zabbix_group['alias'], { auth_token: auth_token, status: "info", text: "Мониторинг временно недоступен (идут обновления)" })
  #             alias_names << zabbix_group['alias']
  #             #print zabbix_group['alias']
  #             #print "\n"
  #end
  #alias_names = alias_names.uniq
  #set :zabbix_widget_names, alias_names
  #next
  ###############################################################

  alias_groups = Hash.new
  (config_parsed['Zabbix']['aliases']).each do |zabbix_group|

     hostgroup_ids = zbx.query(
         :method => "hostgroup.get",
         :params => {
            :filter => {
                 :name => zabbix_group['group_name']
            },
            :output => "groupid"
         }
     )

     (hostgroup_ids).each do |hostgroup_id|
        alias_groups[zabbix_group['alias']] = hostgroup_id['groupid'] + "," +alias_groups[zabbix_group['alias']].to_s
        alias_names << zabbix_group['alias']
     end
  end

  alias_names = alias_names.uniq

  if alias_groups.any?

    alias_groups.each do |alias_name,alias_groups|
      #
      ###############################################################
      # informer for changes
      ###############################################################
      #send_event(alias_name, { auth_token: auth_token, status: "info", text: "Мониторинг временно недоступен (идут обновления)" })
      #next
      ###############################################################
      #

      triggers = []
      items = []
      events = []
      last_priority = -1
      priority = 0
      trigger_name = ""
      trigger_id = ""
      acknowleged_trigger = 0

      #---------- HTML modal box ----------------
      html_modal_string = '<div id="modal-' + alias_name + '" class="modalbg">'
      html_modal_string += '<div class="dialog">'
      html_modal_string += '<a href="#close" title="Закрыть" class="close">X</a>'
      html_modal_string += '<table>'
      html_modal_string += '<tr><th></th><th>Триггер</th><th>Последние данные</th><th>Хост</th><th>Описание</th><th>Время</th><th>Подтверждение</th><th>Влияние</th></tr>'
      #-----------------------------------------

        #Get triggers with state problem
        triggers = zbx.query(
          :method => "trigger.get",
          :params => {
            :filter => {
              :value => 1,
              :status => 0,
              :state => 0
            },
            :monitored => 1,
            :min_severity => 1,
            :skipDependent => 1,
            :expandDescription => 1,
            :groupids => alias_groups.split(","),
            :output => [
              "description",
              "priority",
              "triggerid",
              "state"
            ]
          }
        )

        #If there are triggers
        if triggers.any? #START if trigger any
          counter = 0

          (triggers).each do |trigger|

            # Get items
            items = zbx.query(
               :method => "item.get",
               :params => {
                 :triggerids => trigger['triggerid'],
                 :webitems => true,
                 :monitored => true,
                 :filter => {
                   :status => 0 # Active items only !!!
                 },
                 :output => [
                "itemid"
                 ]
               }
            )

            # GET only triggers with active items !!!
            if items.any?   #START if items any
               counter += 1

               #----- HTML modal box ------------------
               html_modal_string += '<tr>'
               html_modal_string += '<td><div class="priority-' + trigger['priority'] + '"></div></td>'

               hosts = zbx.query(
                   :method => "host.get",
                   :params => {
                     :triggerids => trigger['triggerid'],
                     :output => [
                         "name",
                         "hostid",
                         "host"
                     ]
                   }
               )

               hostid = ""
               hostname = ""
               triggerdescription = ""
               if hosts.any?
                   hostname = hosts[0]['host']
                   (hosts).each do |host|
                       hostid = host['hostid']
                       #hostname = host['host']
                          if trigger['description'].include? "{HOST.NAME}"
                              triggerdescription = trigger['description'].sub("{HOST.NAME}",host['name'])
                          else
                              triggerdescription = trigger['description']
                          end
                    end
               end

               html_modal_string += '<td><a href="http://ru/triggers.php?form=update&hostid=' + hosts[0]['hostid'] + '&triggerid=' + trigger['triggerid'] + '" target="_blank"><p>' + trigger['triggerid'] + '</p></a></td>'
               html_modal_string += '<td><a href="http://.ru/zabbix.php?action=latest.view&filter_hostids%5B%5D=' + hosts[0]['hostid'] + '&filter_set=1" target="_blank"><p>***</p></a></td>'
               html_modal_string += '<td>' + hostname + '</td>'
               html_modal_string += '<td>' + triggerdescription + '</td>'
               #---------------------------------------

               #--- get events ------------
               acknowleged_event = 0
               trigger_priority = 0

               events = zbx.query(
                    :method => "event.get",
                    :params => {
                       :objectids => trigger['triggerid'],
                       :select_acknowledges => "extend",
                       :sortfield => "clock",
                       :sortorder => "DESC",
                       :output => "extend",
                       :limit => 1
                    }
                 )

               if events.any?
                  html_modal_string += '<td>' + DateTime.strptime((events[0]['clock'].to_i + 5*60*60).to_s,'%s').strftime("%Y-%m-%d %H:%M:%S") + '</td>'
                  if events[0]['acknowledged'] == "0"
                     acknowleged_event = 0
                     trigger_priority = trigger['priority'].to_i
                     html_modal_string += '<td><a href="http://ru/zabbix.php?action=popup&popup_action=acknowledge.edit&eventids%5B%5D=' + events[0]['eventid'] + '" target="_blank">Подтвердить?</td>'
                  else
                     acknowleged_event = 1
                     trigger_priority = 0  #lower for acknowleged events
                     acknow_message=""
                     if events[0]['acknowledges'].any?
                          acknow_message = events[0]['acknowledges'][0]['message']
                     end
                     html_modal_string += '<td><a href="http://ru/zabbix.php?action=popup&popup_action=acknowledge.edit&eventids%5B%5D=' + events[0]['eventid'] + '" target="_blank">' + acknow_message + '</td>'
                  end
               else
                  html_modal_string += '<td>Событие не найдено</td>'
               end

               html_modal_string +='<td><a href="http://1/sla/?host=' + hostname + '" target="_blank">Влияние</a></td>'
               #------------------ HTML modal ----------------------
               html_modal_string += '</tr>'
               #----------------------------------------------------

               #Get the greater priority
               if trigger_priority > last_priority         # > show first trigger in group; >= show last trigger in group
                 priority = trigger['priority'].to_i
                 last_priority = priority
                 trigger_name = trigger['description']
                 trigger_id = trigger['triggerid']

                 if acknowleged_event == 1
                    acknowleged_trigger = 1
                    last_priority = -1
                 else
                    acknowleged_trigger = 0
                 end

                 #------ add hostname to trigger description ----------------
                 #if !trigger_name.include_any?([" on "," на "])
                 trigger_name = trigger_name + " (" + hostname + ")"
                 #end
                 #-----------------------------------------------------------

               end # END if trigger last priority

            end #END if items any

          end # END EACH DO triggers

        end #END if trigger any


        #------- HTML modal box -------------
        html_modal_string +=     '</table>'
        html_modal_string +=   '</div>'
        html_modal_string += '</div>'

        #-------- Play Sound ---------------
        if zbx_priorities[priority] == 'high'
            html_modal_string += '<script type="text/javascript">if(document.getElementById("audio_high")!=null) document.getElementById("audio_high").play();</script>'
        end
        if zbx_priorities[priority] == 'warning'
            html_modal_string += '<script type="text/javascript">if(document.getElementById("audio_warning")!=null) document.getElementById("audio_warning").play();</script>'
        end
        if zbx_priorities[priority] == 'average'
            html_modal_string += '<script type="text/javascript">if(document.getElementById("audio_average")!=null) document.getElementById("audio_average").play();</script>'
        end
        if zbx_priorities[priority] == 'information'
            html_modal_string += '<script type="text/javascript">if(document.getElementById("audio_information")!=null) document.getElementById("audio_information").play();</script>'
        end
        if zbx_priorities[priority] == 'disaster'
            html_modal_string += '<script type="text/javascript">if(document.getElementById("audio_disaster")!=null) document.getElementById("audio_disaster").play();</script>'
        end
        #-----------------------------------

        if html_modal_string.include? "priority-"
           if counter > 1
               trigger_name = '<p class="counter">' + counter.to_s + '</p>' + trigger_name + html_modal_string
           else
               trigger_name = trigger_name + html_modal_string
           end
        end
        #------------------------------------

        if acknowleged_trigger == 1
          send_event(alias_name, { auth_token: auth_token, status: zbx_priorities[10], text: trigger_name })
        else
          send_event(alias_name, { auth_token: auth_token, status: zbx_priorities[priority], text: trigger_name })
        end


      end

  end				#----------2---------

  set :zabbix_widget_names, alias_names

end				#----------1---------

