# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Inspired from: https://gist.github.com/cliffano/9868180

# Made changes so  that only reports PASS or FAIL for each task, as csv format.
# outputs in reports/ on current directory
# This plugin is set specific for this auditing. and may not work for all cases. 

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

from ansible.plugins.callback import CallbackBase
try:
    import simplejson as json
except ImportError:
    import json


taskid=''

class CallbackModule(CallbackBase):
    def setTaskID(self,taskname,iscon):
      self.taskid = taskname

    def csv_reporter(self, data,host):
          f = open('reports/'+host+'.csv', 'a')
          summary = open('reports/summary_report.csv', 'a')
          if type(data) == dict:
            status='UNKNOWN'
            output='UNKNOWN'
            keyfound=False
            # set whichever value is available
            try:
              stdout=data['stdout']
            except:
              stdout=""
            try:
              stderr=data['stderr']
            except:
              stderr=""
            try:
              rc=data['rc']
            except:
              rc=''
            try:
              msg=data['msg']
            except:
              msg=""
           
            # following may not work for all cases, but of all the task I'm running seem to work.
            # Most of the task should have failed_when: param, this has field in output called 'failed'.
            # if a message is debug, there is no failed field.

	    # if a task has failed_when param, then 'failed' field will exist. 
            # we first check for this value that.  if it exists outcome is based on this value. 
            #  pass or fail based on 'failed' value.
            try:
                if data['failed'] == True:
                  status='FAIL'
                  keyfound=True
                else:
                  status='PASS'
                  keyfound=True
            except:
                keyfound=False

            # if key is not found, this means the failed field does not exist, 
            # check if its a debug message or used with_item.

            if not keyfound: 
              try:
                # with_items pass with all items completed, failed in msg
                if data['msg'] == 'All items completed':
                  status='PASS'
                  keyfound=True
                elif data['msg'] == 'One or more items failed':
                  status='FAIL'
                elif data['msg'] != []:
                  # else it could just a debug msg, so just display debug msg
  		  status = 'VERIFY'
                  stdout = data['msg']
                  keyfound=True
                elif data['msg'] == []:
                  # else it could just a debug msg, so just display debug msg
  		  status = 'PASS'
                  stdout = data['msg']
                  keyfound=True
              except:
                keyfound=False

            # if a key is not found by this stage
            # this means, files, 'msg' or 'failed' does not exists. 
            # maybe failed_when wasn't used and it is not with_items or debug message
            # check it's command status and if it's a pass
            if not keyfound: 
              if rc == 0:
                  status='PASS'
                  keyfound=True

            if stdout == '':
               stdout = stderr 
            if stderr == '' and msg !='':
               stdout = msg

            
            # only log, only log if we have taskname
            if self.taskid:
              #print("\n{0}, {1}".format(host,status))
              f.write("\n{0}, {1}\n {2}\n".format(self.taskid,status,stdout))
              summary.write("\n{0}, {1}, {2}'".format(self.taskid,host,status))
              

    def on_any(self, *args, **kwargs):
        pass

    def runner_on_failed(self, host, res, ignore_errors=False):
        self.csv_reporter(res,host)

    def runner_on_ok(self, host, res):
        self.csv_reporter(res,host)
        

    def runner_on_error(self, host, msg):
        pass

    def runner_on_skipped(self, host, item=None):
        pass

    def runner_on_unreachable(self, host, res):
        self.csv_reporter(res,host)

    def runner_on_no_hosts(self):
        pass

    def runner_on_async_poll(self, host, res, jid, clock):
        self.csv_reporter(res,host)

    def runner_on_async_ok(self, host, res, jid):
        self.csv_reporter(res,host)

    def runner_on_async_failed(self, host, res, jid):
        self.csv_reporter(res,host)

    def playbook_on_start(self):
        pass

    def playbook_on_notify(self, host, handler):
        pass

    def playbook_on_no_hosts_matched(self):
        pass

    def playbook_on_no_hosts_remaining(self):
        pass

    def playbook_on_task_start(self, name, is_conditional):
        self.setTaskID(name,is_conditional) 

    def playbook_on_vars_prompt(self, varname, private=True, prompt=None,
                                encrypt=None, confirm=False, salt_size=None,
                                salt=None, default=None):
        pass

    def playbook_on_setup(self):
        pass

    def playbook_on_import_for_host(self, host, imported_file):
        pass

    def playbook_on_not_import_for_host(self, host, missing_file):
        pass

    def playbook_on_play_start(self, pattern):
        pass

    def playbook_on_stats(self, stats):
        pass
