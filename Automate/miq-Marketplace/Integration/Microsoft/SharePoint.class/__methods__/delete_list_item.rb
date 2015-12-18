#
# Description: Deletes SharPpoint list item
# Notes: 
# - Use #add message when calling the instance
# - Tested on SharePoint 2010 and SharePoint 2013
# - Works with NTLM, Basic, and Digest authentication only
#

begin
  # ====================================
  # set gem requirements
  # ====================================
  
  require 'httpclient'
  require 'rubyntlm'
  require 'json'
  
  # ====================================
  # define methods
  # ====================================
  
  # define log method
  def log(level, msg)
    $evm.log(level,"#{@org} Customization: #{msg}")
  end

  # log bookends
  def log_bookend(status)
    $evm.log("info", "====================================")
    $evm.log("info", "#{@org} Customization: #{status.capitalize} #{@method} method")
    $evm.log("info", "====================================")
  end

  # dump root attributes
  def dump_root()
    log("info", "Root:<$evm.root> Begin $evm.root.attributes")
    $evm.root.attributes.sort.each { |k, v| log("info", "Root:<$evm.root> Attribute - #{k}: #{v}") }
    log("info", "Root:<$evm.root> End $evm.root.attributes")
    log("info", "")
  end
  
  # find item by id and return the response
  def find_list_item(client, url, headers, vm_name)
    # log what we are doing
    log(:info, "Finding SharePoint list item for VM: #{vm_name}")
    
    # set out query string to find the list object and log it
    query = {
      "\$filter" => "Hostname eq \'#{vm_name}\'"
    }
    log(:info, "Using query string: #{query.inspect}")
    
    # return the response for getting the list item
    client.get(url, query, headers)
  end
  
  # send http delete message to uri containing the item
  def delete_list_item(client, uri, headers)
    # log what we are doing
    log(:info, "Deleting SharePoint list item at: #{uri}")

    # send the delete request and return the response
    client.delete(uri, headers)
  end
  
  # ====================================
  # set variables
  # ====================================

  # set variables related to method
  @method = 'delete_list_item'
  @org = 'My Organization'

  # set variables related to provisioning
  case $evm.root['vmdb_object_type']
  when 'vm'
    vm = $evm.root['vm']
    prov = vm.miq_provision
  when 'miq_provision'
    prov = $evm.root['miq_provision']
    vm = prov.destination
  else
    raise "Invalid $evm.root['vmdb_object_type']: #{$evm.root['vmdb_object_type']}"
  end
  
  # set sharepoint variables
  sp_username = $evm.object['sp_username']
  sp_password = $evm.object.decrypt('sp_password')
  sp_server = $evm.object['sp_server']
  sp_list_name = $evm.object['sp_list_name']
  sp_api_ref = $evm.object['sp_api_ref']
  sp_site = $evm.object['sp_site']
  sp_url_prefix = $evm.object['sp_url_prefix']
  
  # construct url we will talk to
  if sp_site.nil?
    # set variable for a default site list
    url = "#{sp_url_prefix}://#{sp_server}/#{sp_api_ref}/#{sp_list_name}"
  else
    # set variable for a list in a sub-site
    url = "#{sp_url_prefix}://#{sp_server}/#{sp_site}/#{sp_api_ref}/#{sp_list_name}"
  end
  
  # construct headers hash for rest connection and log
  headers = {
    'X-FORMS_BASED_AUTH_ACCEPTED' => 'f',
    'Accept' => 'application/json;odata=verbose'
  }
  log(:info, "Inspecting headers: #{headers.inspect}")
  
  # create new httpcient object
  client = HTTPClient.new
   
  # ====================================
  # begin main method
  # ====================================

  # log entering method
  log_bookend("enter")

  # dump root attributes
  dump_root
  
  # set authentication parameters on httpclient object
  client.set_auth(nil, sp_username, sp_password)
  
  # find the uri of the list item we will be deleting
  get_item_response = find_list_item(client, url, headers, vm.name)
  log(:info, "Inspecting get_item_response: #{get_item_response.inspect}")
  log(:info, "get_item_response returned code: <#{get_item_response.status}>")
  raise "Invalid response code <#{get_item_response.status}> when running method get_item_response.  Expecting code <200>" unless get_item_response.status == 200
  
  # get the body and ultimately the uri where we will be deleting
  body = JSON.parse(get_item_response.body) rescue nil
  raise "Unable to get body from get_item_response" if body.nil?
  log(:info, "Inspecting body: #{body.inspect}")
    
  # return the uri that we will use to delete the list item
  uri =  body['d']['results'].first['__metadata']['uri'] rescue nil
  raise "Unable to determine URI to send HTTP DELETE request to" if uri.nil?
  
  # finally delete the list item and log the return code
  delete_item_response = delete_list_item(client, uri, headers)
  log(:info, "Delete response returned code: <#{delete_item_response.status}>")
  raise "Invalid response code <#{delete_item_response.status}> when running method delete_item_response.  Expecting code <204>" unless delete_item_response.status == 204

  # log exiting method
  log_bookend("exit")
  exit MIQ_OK

# set ruby rescue behavior
rescue => err
  # set error message
  message = "Method #{@method} failed.  Unable to delete SharePoint list item for vm: #{vm.name}"
  
  # log what we failed
  log(:warn, message)
  log(:warn, "[#{err}]\n#{err.backtrace.join("\n")}")

  # get errors variables (or create new hash)
  retire_errors = prov.get_option(:retire_errors) || {}
  
  # set hash with this method error
  retire_errors[:delete_list_item_error] = message
  
  # set errors option
  # NOTE: we can find this option later and send it via e-mail if we wish
  prov.set_option(:retire_errors, retire_errors)
        
  # log exiting method
  log_bookend("exit")
  exit MIQ_WARN
end
