"use strict";

function create_work_item(ticket, process_uri, net_element_uri, parent_uri, _event_id, isTrace)
{
    try
    {
        var new_uri = genUri();
        var new_work_item = {
            '@': new_uri,
            'rdf:type': [
            {
                data: 'v-wf:WorkItem',
                type: _Uri
            }],
            'v-wf:forProcess': [
            {
                data: process_uri,
                type: _Uri
            }],
            'v-wf:forNetElement': [
            {
                data: net_element_uri,
                type: _Uri
            }]
        };

        if (isTrace)
            new_work_item['v-wf:isTrace'] = newBool(true);

        if (parent_uri !== null)
        {
            new_work_item['v-wf:previousWorkItem'] = [
            {
                data: parent_uri,
                type: _Uri
            }];
        }

        //print("[WORKFLOW]:create work item:" + new_uri);

        put_individual(ticket, new_work_item, _event_id);

        addRight(ticket, [can_read], "v-wf:WorkflowReadUser", new_uri);

        return new_uri;
    }
    catch (e)
    {
        print(e.stack);
    }

}

function WorkItemResult(_work_item_result)
{
    this.work_item_result = _work_item_result;

    /////////////////////////// functions prepare work_item_result
    this.getValue = function(var_name)
    {
        //print("%%%1");
        for (var i in this.work_item_result)
        {
            //print("%%%2");
            return this.work_item_result[i][var_name];
        }
        //print("%%%3");
    };

    this.compare = function(var_name, value)
    {
        //print ("@@@compareTaskResult this.work_item_result=", toJson (this.work_item_result));
        //print ("@@@compareTaskResult value=", toJson (value));
        //print ("@@@compareTaskResult var_name=", toJson (var_name));
        if (!this.work_item_result || this.work_item_result.length == 0)
            return false;

        if (value.length > 0)
        {
            //	print ("@@@compareTaskResult 1");
            var true_count = 0;
            for (var i in this.work_item_result)
            {
                //	print ("@@@compareTaskResult 2");
                var wirv = this.work_item_result[i][var_name];
                if (wirv && wirv.length == value.length)
                {
                    //	print ("@@@compareTaskResult 3");
                    for (var j in wirv)
                    {
                        //	print ("@@@compareTaskResult 4");
                        for (var k in value)
                        {
                            if (wirv[j].data == value[k].data && wirv[j].type == value[k].type)
                                true_count++;

                        }
                        if (true_count == value.length)
                            return true;
                    }
                }
            }
        }

        return false;
    };


    this.is_all_executors_taken_decision = function(var_name, value)
    {
        var count_agreed = 0;
        for (var i = 0; i < this.work_item_result.length; i++)
        {
            var wirv = this.work_item_result[i][var_name];

            print("@@@is_all_executors_taken_decision: wiri=" + toJson(wirv), ", value=", toJson(value));

            if (wirv && wirv.length > 0 && wirv[0].data == value[0].data && wirv[0].type == value[0].type)
                count_agreed++;
        }

        if (count_agreed == this.work_item_result.length)
        {
            print("@@@is_some_executor_taken_decision: TRUE");
            return true;
        }
        else
            return false;

    };

    this.is_some_executor_taken_decision = function(var_name, value)
    {
        for (var i = 0; i < this.work_item_result.length; i++)
        {
            var wirv = this.work_item_result[i][var_name];

            print("@@@is_some_executor_taken_decision: wiri=" + toJson(wirv), ", value=", toJson(value));

            if (wirv && wirv.length > 0 && wirv[0].data == value[0].data && wirv[0].type == value[0].type)
            {
                print("@@@is_some_executor_taken_decision: TRUE");
                return true;
            }
        }

        return false;
    }


}

function Context(_src_data, _ticket)
{
    this.src_data = _src_data;
    this.ticket = _ticket;

    this.getExecutor = function()
    {
        return this.src_data['v-wf:executor'];
    };

    this.get_results = function()
    {
        return this.src_data;
    };

    this.if_all_executors_taken_decision = function(true_decision, false_decision)
    {
        try
        {
            var count_agreed = 0;
            for (var i = 0; i < this.src_data.length; i++)
            {
                //	   print ("data[i].result=", data[i].result);
                if (this.src_data[i].result == true_decision)
                {
                    count_agreed++;
                }
            }

            if (count_agreed == this.src_data.length)
            {
                return [
                {
                    'data': true_decision,
                    'type': _Uri
                }];
            }
            else
            {
                return [
                {
                    'data': false_decision,
                    'type': _Uri
                }];
            }
        }
        catch (e)
        {
            print(e.stack);
            return false;
        }

    };

    this.getInputVariable = function(var_name)
    {
        return this.getVariableValueIO(var_name, 'v-wf:inVars');
    }

    this.getLocalVariable = function(var_name)
    {
        return this.getVariableValueIO(var_name, 'v-wf:localVars');
    }

    this.getOutVariable = function(var_name)
    {
        return this.getVariableValueIO(var_name, 'v-wf:outVars');
    }

    this.getVariableValueIO = function(var_name, io)
    {
        try
        {
            //        	print ("CONTEXT::getVariableValueIO src_data=" + toJson (this.src_data));
            var variables = this.src_data[io];

            if (variables)
            {
                for (var i = 0; i < variables.length; i++)
                {
                    var variable = get_individual(this.ticket, variables[i].data);
                    if (!variable) continue;
                    //print ("CONTEXT::getVariableValueIO var=" + toJson (variable));

                    var variable_name = getFirstValue(variable['v-wf:variableName']);

                    //print("[WORKFLOW]:getVariableIO #0: work_item=" + this.src_data['@'] + ", var_name=" + variable_name + ", val=" + toJson(variable['v-wf:variableValue']));

                    if (variable_name == var_name)
                    {
                        var val = variable['v-wf:variableValue'];

                        //print("[WORKFLOW]:getVariableValue #1: work_item=" + this.src_data['@'] + ", var_name=" + var_name + ", val=" + toJson(val)); // + ", variable=" + toJson (variable));
                        return val;
                    }
                }

            }
        }
        catch (e)
        {
            print(e.stack);
            return false;
        }

        //print("[WORKFLOW]:getVariableValue: work_item=" + this.src_data['@'] + ", var_name=" + var_name + ", val=undefined");
    };

    this.print_variables = function(io)
    {
        try
        {
            var variables = this.src_data[io];

            if (variables)
            {
                for (var i = 0; i < variables.length; i++)
                {
                    var variable = get_individual(this.ticket, variables[i].data);
                    if (!variable) continue;

                    var variable_name = getFirstValue(variable['v-wf:variableName']);

                    //print("[WORKFLOW]:print_variable: work_item=" + this.src_data['@'] + ", var_name=" + variable_name + ", val=" + toJson(variable['v-wf:variableValue']));
                }

            }
        }
        catch (e)
        {
            print(e.stack);
            return false;
        }

    };

    this.get_result_value = function(field1, type1)
    {
        try
        {
            if (this.src_data && this.src_data.length > 0)
            {
                var rr = this.src_data[0][field1];
                if (rr)
                    return [
                    {
                        'data': rr,
                        'type': type1
                    }];
                else
                    return null;
            }
        }
        catch (e)
        {
            print(e.stack);
            return false;
        }

    };
}

function get_new_variable(variable_name, value)
{
    try
    {
        var new_uri = genUri();
        var new_variable = {
            '@': new_uri,
            'rdf:type': [
            {
                data: 'v-wf:Variable',
                type: _Uri
            }],
            'v-wf:variableName': [
            {
                data: variable_name,
                type: _String
            }]
        };

        if (value)
            new_variable['v-wf:variableValue'] = value;

        return new_variable;
    }
    catch (e)
    {
        print(e.stack);
        throw e;
    }

}

function store_items_and_set_minimal_rights(ticket, data)
{
    try
    {
        var ids = [];
        for (var i = 0; i < data.length; i++)
        {
            put_individual(ticket, data[i], _event_id);
            ids.push(
            {
                data: data[i]['@'],
                type: _Uri
            });
            addRight(ticket, [can_read], "v-wf:WorkflowReadUser", data[i]['@']);
        }
        return ids;
    }
    catch (e)
    {
        print(e.stack);
    }
}

function generate_variable(ticket, def_variable, value, _process, _task, _task_result)
{
    try
    {
        var variable_name = getFirstValue(def_variable['v-wf:varDefineName']);

        //print("[WORKFLOW][generate_variable]: variable_define_name=" + variable_name);
        var new_variable = get_new_variable(variable_name, value)

        var variable_scope = getUri(def_variable['v-wf:varDefineScope']);
        if (variable_scope)
        {
            var scope;
            if (variable_scope == 'v-wf:Net')
                scope = _process['@'];

            if (scope)
            {
                new_variable['v-wf:variableScope'] = [
                {
                    data: scope,
                    type: _Uri
                }];

                var local_vars = _process['v-wf:localVars'];
                var find_local_var;
                if (local_vars)
                {
                    //print("[WORKFLOW][generate_variable]: ищем переменную среди локальных");

                    // найдем среди локальных переменных процесса, такую переменную
                    // если нашли, то новая переменная должна перезаписать переменную процесса

                    for (var i = 0; i < local_vars.length; i++)
                    {
                        var local_var = get_individual(ticket, local_vars[i].data);
                        if (!local_var) continue;

                        var var_name = getFirstValue(local_var['v-wf:variableName']);
                        if (!var_name) continue;

                        if (var_name == variable_name)
                        {
                            find_local_var = local_var;
                            break;
                        }
                    }

                    if (find_local_var)
                        new_variable['@'] = find_local_var['@'];
                }

                if (!find_local_var)
                {
                    //print("[WORKFLOW][generate_variable]: не, найдена, привязать новую к процессу:" + _process['@']);

                    // если не нашли то привязать новую переменную к процессу
                    var add_to_document = {
                        '@': _process['@'],
                        'v-wf:localVars': [
                        {
                            data: new_variable['@'],
                            type: _Uri
                        }]
                    };
                    add_to_individual(ticket, add_to_document, _event_id);
                }

            }
        }

        //print("[WORKFLOW][generate_variable]: new variable: " + toJson(new_variable));

        return new_variable;
    }
    catch (e)
    {
        print(e.stack);
        throw e;
    }

}

function create_and_mapping_variables(ticket, mapping, _process, _task, _order, _task_result, f_store, trace_journal_uri, trace_comment)
{
    try
    {
		var _trace_info = [];
				
        var new_vars = [];
        if (!mapping) return [];

        var process;
        var task;
        var order;
        var task_result;

        if (_process)
            process = new Context(_process, ticket);

        if (_task)
            task = new Context(_task, ticket);

        if (_order)
            order = new Context(_order, ticket);

        if (_task_result)
            task_result = new WorkItemResult(_task_result);

        for (var i = 0; i < mapping.length; i++)
        {
            var map = get_individual(ticket, mapping[i].data);

            if (map)
            {
                //print("[WORKFLOW][create_and_mapping_variables]: map_uri=" + map['@']);
                var expression = getFirstValue(map['v-wf:mappingExpression']);
                if (!expression) continue;

                //print("[WORKFLOW][create_and_mapping_variables]: expression=" + expression);
                try
                {
                    var res1 = eval(expression);
                    //print("[WORKFLOW][create_and_mapping_variables]: res1=" + toJson(res1));
                    if (!res1) continue;

                    var mapToVariable_uri = getUri(map['v-wf:mapToVariable']);
                    if (!mapToVariable_uri) continue;

                    var def_variable = get_individual(ticket, mapToVariable_uri);
                    if (!def_variable) continue;

                    var new_variable = generate_variable(ticket, def_variable, res1, _process, _task, _task_result);
                    if (new_variable)
                    {
                        if (f_store == true)
                        {
                            put_individual(ticket, new_variable, _event_id);

							if (trace_journal_uri)
								_trace_info.push(new_variable);								

                            new_vars.push(
                            {
                                data: new_variable['@'],
                                type: _Uri
                            });
                            addRight(ticket, [can_read], "v-wf:WorkflowReadUser", new_variable['@']);

                        }
                        else
                        {
                            new_vars.push(new_variable);
                        }
                    }
                }
                catch (e)
                {
					if (trace_journal_uri)
						traceToJournal(ticket, trace_journal_uri, "create_and_mapping_variables", "err: expression: " + expression + "\n" + e.stack);							
                }
            }
            else
            {
				if (trace_journal_uri)
					traceToJournal(ticket, trace_journal_uri, "create_and_mapping_variables", "map not found :" + mapping[i].data);							
            }
        }

		if (trace_journal_uri)
			traceToJournal(ticket, trace_journal_uri, "create_and_mapping_variables", trace_comment + " = '" + getUris (mapping) + "' \n\nout = \n" + toJson(_trace_info));							

        return new_vars;
    }
    catch (e)
    {
        print(e.stack);
        return [];
    }

}
//////////////////////////////////////////////////////////////////////////
function is_exists_result(data)
{
    for (var i = 0; i < data.length; i++)
    {
        if (data[i].result)
            return true;
    }

    return false;
}

//////////////////////////////////////////////////////////////////////////

function find_in_work_item_tree(ticket, _process, compare_field, compare_value)
{
    try
    {
        var res = [];

        var f_workItemList = _process['v-wf:workItemList'];

        if (f_workItemList)
            rsffiwit(ticket, f_workItemList, compare_field, compare_value, res, _process);

        return res;
    }
    catch (e)
    {
        print(e.stack);
    }
}

function rsffiwit(ticket, work_item_list, compare_field, compare_value, res, _parent)
{
    try
    {
        for (var idx = 0; idx < work_item_list.length; idx++)
        {
            var i_work_item = get_individual(ticket, work_item_list[idx].data);
            if (i_work_item)
            {
                var ov = i_work_item[compare_field];
                var isCompleted = i_work_item['v-wf:isCompleted'];

                if (ov && getUri(ov) == compare_value && !isCompleted)
                    res.push(
                    {
                        parent: _parent,
                        work_item: i_work_item
                    });

                var f_workItemList = i_work_item['v-wf:workItemList'];

                if (f_workItemList)
                    rsffiwit(ticket, f_workItemList, compare_field, compare_value, res, i_work_item);
            }

        }
    }
    catch (e)
    {
        print(e.stack);
    }


}

///////////////////////////////////////////// JOURNAL //////////////////////////////////////////////////

function create_new_journal(ticket, new_journal_uri, process_uri, label)
{
    try
    {
	var exists_journal = get_individual (ticket, new_journal_uri);
	
	if (!exists_journal)
	{
        var new_journal = {
            '@': new_journal_uri,
            'rdf:type': [
            {
                data: 'v-s:Journal',
                type: _Uri
            }]
        };

		if (process_uri)
            new_journal['v-wf:onProcess'] = newUri (process_uri);
		
        if (label)
            new_journal['rdfs:label'] = label;

        put_individual(ticket, new_journal, _event_id);
		//print ("@@@ create new journal, =", toJson (new_journal))
	}

        return new_journal_uri;
    }
    catch (e)
    {
        print(e.stack);
    }

}

function mapToJournal(map_container, ticket, _process, _task, _order)
{
    try
    {
        //print ("@mapToJournal.1");
        if (map_container)
        {
            //* выполнить маппинг для журнала 
            var journalVars = [];

            journalVars = create_and_mapping_variables(ticket, map_container, _process, _task, _order, null, false, null);
            if (journalVars)
            {
                var jornal_uri = getJournalUri(_process['@']);
                var new_journal_record = newJournalRecord(jornal_uri);

                for (var idx = 0; idx < journalVars.length; idx++)
                {
                    var jvar = journalVars[idx];
                    var name = getFirstValue(jvar['v-wf:variableName']);
                    var value = jvar['v-wf:variableValue'];

                    //print("@mapToJournal.2 name=" + name + ", value=" + toJson(value));
                    new_journal_record[name] = value;
                }
                logToJournal(ticket, jornal_uri, new_journal_record);
            }
        }
    }
    catch (e)
    {
        print(e.stack);
    }

}

function create_new_trace_subjournal(parent_uri, net_element_impl, label, type)
{
    var isTrace = net_element_impl['v-wf:isTrace'];
    if (isTrace && getFirstValue(isTrace) == true)
    {
        var new_sub_journal_uri = getTraceJournalUri(net_element_impl['@']);
        create_new_journal(ticket, new_sub_journal_uri, null, label);

        var parent_journal_uri = getTraceJournalUri(parent_uri);
        var new_journal_record = newJournalRecord(parent_journal_uri);

        new_journal_record['rdf:type'] = [
        {
            data: type,
            type: _Uri
        }];
        new_journal_record['rdfs:label'] = [
        {
            data: 'запущен элемент сети',
            type: _String
        }];
        new_journal_record['v-s:subJournal'] = [
        {
            data: new_sub_journal_uri,
            type: _Uri
        }];
        logToJournal(ticket, parent_journal_uri, new_journal_record);

		put_individual(ticket, new_journal_record, _event_id);

		var add_to_net_element_impl = {
        '@': net_element_impl['@'],
        'v-wf:traceJournal': newUri (new_sub_journal_uri)
        };

		add_to_individual(ticket, add_to_net_element_impl, _event_id);

        return new_sub_journal_uri;
    }
    else
    {
        return undefined;
    }
}

function get_trace_journal(document, process)
{
    var isTrace = document['v-wf:isTrace'];
    if (isTrace && getFirstValue(isTrace) == true)
    {
        return getTraceJournalUri(process['@']);
    }
    else
    {
        return undefined;
    }
}

/////////////////////////////////////////////////////////////////////////////////////////

function create_new_subprocess(ticket, f_useSubNet, f_executor, parent_net, f_inVars, document, parent_trace_journal_uri)
{
    try
    {
        var parent_process = document['@'];

        var use_net;

        if (f_useSubNet)
            use_net = f_useSubNet;
        else
            use_net = f_executor;

		if (parent_trace_journal_uri)
			traceToJournal(ticket, parent_trace_journal_uri, "[WO2.4] executor= " + getUri(f_executor) + " used net", getUri(use_net));							

        //var ctx = new Context(work_item, ticket);
        //ctx.print_variables ('v-wf:inVars');
        var _started_net = get_individual(ticket, getUri(use_net));
        if (_started_net)
        {
            var new_process_uri = genUri();

            var new_process = {
                '@': new_process_uri,
                'rdf:type': [
                {
                    data: 'v-wf:Process',
                    type: _Uri
                }],
                'v-wf:instanceOf': use_net,
                'v-wf:parentWorkOrder': [
                {
                    data: parent_process,
                    type: _Uri
                }]
            };

            var msg = "экземпляр маршрута :" + getFirstValue(_started_net['rdfs:label']) + ", запущен из " + getFirstValue(parent_net['rdfs:label'])

            if (f_useSubNet)
                msg += ", для " + getUri(f_executor);

            new_process['rdfs:label'] = [
            {
                data: msg,
                type: _String
            }];

            // возьмем входные переменные WorkItem	и добавим их процессу
            if (f_inVars)
                new_process['v-wf:inVars'] = f_inVars;

            if (f_useSubNet)
                new_process['v-wf:executor'] = f_executor;

			if (parent_trace_journal_uri)
			{
				traceToJournal(ticket, parent_trace_journal_uri, "new_process=", getUri(use_net), toJson(new_process));							
				new_process['v-wf:isTrace'] = newBool(true);

				var trace_journal_uri = getTraceJournalUri(new_process_uri);
				create_new_journal(ticket, trace_journal_uri, null, _started_net['rdfs:label']);
				new_process['v-wf:traceJournal'] = newUri (trace_journal_uri);				
			}
			
            put_individual(ticket, new_process, _event_id);

            var journal_uri = getJournalUri(new_process_uri);
            var new_journal_record = newJournalRecord(journal_uri);

            new_journal_record['rdf:type'] = [
            {
                data: 'v-wf:SubProcessStarted',
                type: _Uri
            }];
            new_journal_record['rdfs:label'] = [
            {
                data: 'запущен подпроцесс',
                type: _String
            }];
            new_journal_record['v-s:subJournal'] = [
            {
                data: getJournalUri(new_process_uri),
                type: _Uri
            }];
            logToJournal(ticket, journal_uri, new_journal_record);

            document['v-wf:isProcess'] = [
            {
                data: new_process_uri,
                type: _Uri
            }];
                        
            put_individual(ticket, document, _event_id);
        }
    }
    catch (e)
    {
        print(e.stack);
    }

}


function get_properties_chain(var1, query)
{
    var res = [];

    if (query.length < 1)
        return res;

    var doc;
//    print('@@@get_properties_chain#1 var1=', toJson(var1));
    doc = get_individual(ticket, getUri(var1));

    if (doc)
        traversal(doc, query, 0, res);

//    print('@@@get_properties_chain #2 res=', toJson(res));

    return res;
}

function traversal(indv, query, pos_in_path, result)
{
    var condition = query[pos_in_path];

    //print('@@@ traversal#0 condition=', toJson(condition), ", indv=", toJson(indv));

    var op_get;
    var op_go;
    var op_eq;
    for (var key in condition)
    {
        var op = key;

        if (op == '$get')
            op_get = condition[key];

        if (op == '$go')
            op_go = condition[key];

        if (op == '$eq')
            op_eq = condition[key];
    }
    if (op_go)
    {
        var ffs = indv[op_go];

        for (var i in ffs)
        {
            //print('@@@ traversal#2 ffs[i]=', ffs[i].data);
            var doc = get_individual(ticket, ffs[i].data);
            //print('@@@ traversal#4 doc=', toJson(doc));
            traversal(doc, query, pos_in_path + 1, result);
        }
    }

    if (op_get)
    {
        var is_get = true;
        if (op_eq)
        {
            is_get = false;

            var kk = Object.keys(op_eq);
            if (kk)
            {
                var field = kk[0];

                var A = indv[field];
                if (A)
                {
                    //print("###1 A=", toJson(A));
                    var B = op_eq[field];
                    //print("###2 B=", toJson(B));

                    for (var i in A)
                    {
                        if (A[i].type == B[0].type && A[i].data == B[0].data)
                        {
                            is_get = true;
                    //print("###3 A == B");
                            break;
                        }

                    }

                }
            }
        }

        if (is_get)
        {
            var ffs = indv[op_get];

            for (var i in ffs)
            {
                //print('@@@ traversal#3 push ', ffs[i].data);
                result.push(ffs[i]);
            }
        }
    }

}
