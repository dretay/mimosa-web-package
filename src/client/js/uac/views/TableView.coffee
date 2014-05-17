#
# Backbone dataTables view base class.
#
define (require) ->
    $ = require 'jquery'
    Backbone = require 'backbone'
    Marionette = require 'marionette'

    Evented = require 'uac/common/mixins/Evented'
    vent = require 'uac/common/vent'
    utils = require 'uac/common/utils'

    datatables = require 'datatables'
    datatables_bootstrap = require 'datatables_bootstrap'
    datatables_scroller = require 'datatables-scroller'


    $.extend $.fn.dataTableExt.oSort, {
        "int-html-pre": (a) ->
            x = String(a).replace(/<[\s\S]*?>/g, "")
            return parseInt x
        ,
        "int-html-asc": ( a, b ) ->
            return (if a < b then -1 else (if a > b then 1 else 0))
        ,
        "int-html-desc": ( a, b ) ->
            return (if a < b then 1 else (if a > b then -1 else 0))
    }

    #
    # Base table view class.  Extend this class and provide a configure function to setup your table.
    #
    # Example usage:
    #
    #     # Specify the settings via inheritance.
    #     class MyTable extends TableView
    #         configure: (options) ->
    #              # Add DataTables settings to the options.
    #              options.iDisplayLength = 100
    #     my_table = new MyTable()
    #     my_table.render()
    #
    # or
    #    # Pass in the datatables settings.
    #    settings = {...}
    #    my_table = new TableView({settings: settings})
    #
    class TableView extends Marionette.ItemView
        #
        # Initialize the table the defaults.
        #
        initialize: (options) ->
            super options

            @instanceName = @getInstanceName()

            # Create a container for managing child views.  The container will be closed and emptied on destroy.
            @container = new Backbone.ChildViewContainer()

            if options
                @options = options
            else
                @options = {}

            # Listen to get status events.
            @registerSync
                constructorName: TableView
                instanceName: @instanceName
                eventName: 'status'
                handler: => @get_status_data()

            @listenTo @, 'click', =>
                # Trigger a global click/change event.
                @fireAsync
                    constructorName: TableView
                    eventName: 'change'
                    payload: @get_status_data()
                @fireAsync
                    constructorName: TableView
                    eventName: 'click'
                    payload: @get_selected_data()
                return

            @listenTo @, 'load', =>
                # Trigger a global load event.
                @fireAsync
                    constructorName: TableView
                    instanceName: @instanceName
                    eventName: 'load'
                    payload: @get_status_data()

            @listenTo @, 'empty', =>
                @fireAsync
                    constructorName: TableView
                    instanceName: @instanceName
                    eventName: 'empty'

            # Listen to prev/next change events.
            @registerAsync
                constructorName: TableView
                instanceName: @instanceName
                eventName: 'set_prev'
                handler: => @prev()
            @registerAsync
                constructorName: TableView
                instanceName: @instanceName
                eventName: 'set_next'
                handler: => @next()

            # Listen to draw events to account for the fact that datatables does not fire page change events.  This code
            # makes up for that shortcoming by manually determining when the user has used the previous next component to
            # page through the table.
            @listenTo @, "draw", =>
                if @_page_prev
                    console.debug 'Handling page prev operation...'

                    display_length = @get_settings()._iDisplayLength
                    nodes = @get_nodes()
                    if nodes.length == @get_total_rows()
                        # Collection based backing.
                        prev_index = (@get_current_page() * display_length) - 1
                        last_index = @get_total_rows() - 1
                        if  last_index < prev_index
                            prev_index = last_index
                        @select_row prev_index
                    else
                        # Server side based backing.
                        @select_row @length() - 1

                    # User has iterated through the table to the previous page.
                    @trigger "page", @get_current_page()

                    # Clear the flag.
                    @_page_prev = false

                else if @_page_next
                    console.debug 'Handling page next operation...'

                    display_length = @get_settings()._iDisplayLength
                    nodes = @get_nodes()
                    if nodes.length == @get_total_rows()
                        # Probably using collections, there are more nodes than the display length.  Select the first
                        # row of this page.
                        current_page = @get_current_page()
                        current_row = (current_page * display_length) - display_length
                        @select_row current_row
                    else
                        # Probably using server side processing, the number of rows is equal to the display length,
                        # select the first row.
                        @select_row 0

                    # User has iterated to through the table to the next page.
                    @trigger "page", @get_current_page()

                    # Clear the flag.
                    @_page_next = false

                if @_row_index isnt undefined
                    # During a refresh reload operation a row index to select has been specified.  Attempt to select
                    # the row that corresponds to the index.
                    @select_row @_row_index
                    @_row_index = undefined

                else if @_value_pair

                    # During a refresh/reload operation a value to select has been specified.  Attempt to select the
                    # row that corresponds to the supplied name value pair.
                    console.debug "Attempting to reselect table row value: name=#{@_value_pair.name}, value=#{@_value_pair.value}"

                    # Attempt to select the row related to the value pair after a draw event.
                    matching_row = @select_row_for_value(@_value_pair.name, @_value_pair.value)

                    if not matching_row
                        # If the matching row was not found it is assumed that it was deleted, select the first
                        # row instead.
                        @select_row 0

                    # Clear the value pair.
                    @_value_pair = undefined

                return # End @listenTo @, "draw", =>

        #
        # Visually highlight the row.
        #
        highlight_row: (row) ->
            # Make all visible rows inactive.
            all_rows = @get_nodes()
            $(all_rows).removeClass "active"
            if row
                # Select the row.
                $(row).addClass("active")
            return

        #
        # Initiate a click event on a row.
        # @param index_or_node - the row index or row node.
        # @returns the row node or undefined.
        #
        select_row: (index_or_node) ->
            console.info "Selecting row #{index_or_node} for table #{@instanceName}"

            if not index_or_node?
                # Un-select all rows.
                @highlight_row null
            else if typeof index_or_node is "number"
                # A node index has been supplied.
                length = @length()
                if @length() <= 0 or index_or_node + 1 > length
                    console.debug "Requesting to select index: #{index_or_node} that is not valid."
                    return undefined
                else
                    pos = @get_selected_position()
                    if pos != index_or_node
                        # Only select if we are not already on the row.
                        node = @get_nodes(index_or_node)
                        if node
                            $(node).click()
                        return node
                    else
                        undefined
            else if index_or_node
                # An actual node has been supplied.
                $(index_or_node).click()
                return index_or_node
            else
                # ???
                return undefined

        #
        # Attempt to select the row for the name and value.
        #
        select_row_for_value: (name, value) ->
            nodes = @get_nodes()
            if nodes
                for node in @get_nodes()
                    data = @get_data node
                    if name and value and data[name] == value
                        # Select the node.
                        @select_row node
                        return node
            else
                return null

        #
        # Attempt to highlight the row for the name and value.
        #
        highlight_row_for_value: (name, value) ->
            nodes = @get_nodes()

            if nodes
                for node in @get_nodes()
                    data = @get_data node
                    if name and value and data[name] == value
                        # Select the node.
                        @highlight_row node
                        return node
            else
                return null

        #
        # Retrieve the selected table row.
        #
        get_selected: ->
            @$ "tr.active"

        #
        # Return the position of the selected item.
        #
        get_selected_position: ->
            selected = @get_selected()

            if selected and selected.length is 1
                @get_position selected.get(0)
            else
                -1

        #
        # Return the data for the selected row.
        #
        get_selected_data: ->
            selected = @get_selected()
            if selected isnt undefined and selected.length is 1
                pos = @get_position(selected.get(0))
                @get_data pos
            else
                undefined

        #
        # Return the current page number.
        #
        get_current_page: ->
            settings = @get_settings()
            Math.ceil(settings._iDisplayStart / settings._iDisplayLength) + 1

        #
        # Retrieve the row count.
        #
        get_total_rows: ->
            if @get_settings().oInit.bServerSide
                @get_settings()._iRecordsTotal
            else
                @get_nodes().length

        #
        # Retrieve the page count.
        #
        get_total_pages: ->
            settings = @get_settings()
            Math.ceil @get_total_rows() / settings._iDisplayLength

        #
        # Return whether there is a previous record to navigate to.
        #
        is_prev: ->
            pos = @get_selected_position()
            is_prev = pos > 0 or @get_current_page() > 1
            console.debug "#{@instanceName}:is_prev: #{is_prev}"
            return is_prev

        #
        # Return whether there is a next record to navigate to.
        #
        is_next: ->
            pos = @get_selected_position()
            is_next = pos + 1 < @get_total_rows()
            console.debug "#{@instanceName}:is_next: #{is_next}"
            return is_next

        #
        # Return the previous rows data or undefined.
        #
        peek_prev_data: ->
            selected = @get_selected()
            if selected isnt undefined and selected.length is 1
                pos = @get_position(selected.get(0))
                return @get_data(pos - 1)

            # No previous.
            undefined

        #
        # Return the next rows data or undefined.
        #
        peek_next_data: ->
            if @is_next()
                selected = @get_selected()
                if selected isnt undefined and selected.length is 1
                    pos = @get_position(selected.get(0))
                    return @get_data(pos + 1)

            # No next.
            undefined

        #
        # Navigate to the previous row.  If at the first row in a page then attempt to navigate to the previous page.
        #
        prev: ->
            selected = @get_selected()
            if selected?
                # There is a currently selected row.

                if selected.length > 1
                    # Error, only support singular row selection.
                    console.error 'More than one row selected!'
                    console.dir selected

                if @is_prev()
                    # There is a previous record.

                    pos = @get_position(selected.get(0))
                    display_length = @get_settings()._iDisplayLength
                    nodes = @get_nodes()
                    total_rows = @get_total_rows()
                    first_index_in_page = display_length * (@get_current_page() - 1)

                    #                    console.debug 'Attempting to select the next record...'
                    #                    console.debug "Total rows: #{total_rows}"
                    #                    console.debug "Position: #{pos}"
                    #                    console.debug "Display Length: #{display_length}"
                    #                    console.dir nodes
                    #                    console.debug "Last index in page: #{last_index_in_page}"

                    if total_rows == nodes.length
                        # Using collections based backing.
                        if pos == first_index_in_page
                            if @is_prev_page()
                                # On the first row of the page.
                                @prev_page()
                        else
                            # Not on the last row, increment the row.
                            @select_row pos - 1
                    else
                        # Using server side backing.
                        if pos == 0
                            if @is_prev_page()
                                # On the last row of the page.
                                @prev_page()
                        else
                            # Not on the last row, increment the row.
                            @select_row pos - 1
                else
                    # There is not a previous row to navigate to.
                    console.debug 'No previous record to navigate to.'
            else
                # There is not current selected record, skip.
                console.debug 'No currently selected record, skipping prev...'
            return

        #
        # Navigate to the next row.  If at the last row in a page then attempt to navigate to the next page.
        #
        next: ->
            selected = @get_selected()
            if selected?
                # There is a currently selected row.

                if selected.length > 1
                    # Error, only support singular row selection.
                    console.error 'More than one row selected!'
                    console.dir selected

                if @is_next()
                    # There is a next record.

                    pos = @get_position(selected.get(0))
                    display_length = @get_settings()._iDisplayLength
                    nodes = @get_nodes()
                    total_rows = @get_total_rows()
                    last_index_in_page = (display_length * @get_current_page()) - 1

#                    console.debug 'Attempting to select the next record...'
#                    console.debug "Total rows: #{total_rows}"
#                    console.debug "Position: #{pos}"
#                    console.debug "Display Length: #{display_length}"
#                    console.dir nodes
#                    console.debug "Last index in page: #{last_index_in_page}"

                    if total_rows == nodes.length
                        # Using collections based backing.
                        if pos == last_index_in_page
                            if @is_next_page()
                                # On the last row of the page.
                                @next_page()
                        else
                            # Not on the last row, increment the row.
                            @select_row pos + 1
                    else
                        # Using server side backing.
                        if pos == display_length - 1
                            # On the last row of the page.
                            if @is_next_page()
                                @next_page()
                        else
                            # Not on the last row, increment the row.
                            @select_row pos + 1

                else
                    # There is not a next row.
                    console.debug "No next row to navigate to."
            else
                # There is not current selected record, skip.
                console.debug 'No currently selected record, skipping next...'
            return

        #
        # Return whether there is a previous page to navigate to.
        #
        is_prev_page: ->
            @get_current_page() isnt 1

        #
        # Return whether there is a next page to navigate to.
        #
        is_next_page: ->
            @get_current_page() < @get_total_pages()

        #
        # Navigate to the previous page.
        #
        prev_page: ->
            if @is_prev_page()
                # set page takes an index.
                @set_page(@get_current_page() - 2)
            return

        #
        # Navigate to the next page.
        #
        next_page: ->
            if @is_next_page()
                # set page takes an index.
                @set_page(@get_current_page())
            return

        #
        # Set the current page of the table.
        # @param page_index - the zero based page index.
        #
        set_page: (page_index) ->
            current_page = @get_current_page()
            if page_index + 1 > current_page
                @_page_next = true
            else
                @_page_prev = true
            @table_el.fnPageChange page_index

        #
        # Return the lenth of the data.
        #
        length: ->
            @table_el.fnGetData().length

        #
        #
        #
        get_all_rows: ->
            if @table_el
                return @table_el.find('tbody > tr')
            else
                return []

        #
        # Retrieve the original HTML DOM table element.
        #
        get_dom_table: ->
            @table_el.get 0

        #
        # Return the dataTable.
        #
        get_table: ->
            @table_el

        #
        # Retrieve the table nodes or the node corresponding to index.
        #
        get_nodes: (index) ->
            @table_el.fnGetNodes index

        #
        # Update a row and column with the specified data.
        #
        update: (data, tr_or_index, col_index, redraw, predraw) ->
            @table_el.fnUpdate data, tr_or_index, col_index, redraw, predraw

        #
        # Draw the dataTable.
        #
        draw: (re) ->
            @table_el.fnDraw re
            return

        #
        # Retrieve the table data.
        #
        get_data: (index_or_node, index) ->
            @table_el.fnGetData index_or_node, index

        #
        # Return the posotion of the node.
        #
        get_position: (node) ->
            @table_el.fnGetPosition node

        #
        # Retrieve the index of the node relative to the entire result set.
        #
        get_absolute_index: (node) ->
            if @get_settings().oInit.bServerSide
                (@get_current_page() - 1) * @get_settings()._iDisplayLength + @get_position(node)
            else
                @get_position node

        #
        # Retrieve the dataTable settings.
        #
        get_settings: ->
            @table_el.fnSettings()

        #
        # Retrieve the current search term.
        #
        get_search: ->
            result = ""
            settings = @get_settings()
            result = settings.oPreviousSearch.sSearch  if settings.oPreviousSearch and settings.oPreviousSearch.sSearch
            result

        #
        # Retrieve whether the current element contains an initialized dataTable.
        #
        is_datatable: ->
            $.fn.DataTable.fnIsDataTable @get_dom_table()

        #
        # Retrieve whether server side processing is currently enabled.
        #
        is_server_side: ->
            @get_settings().oInit.bServerSide

        #
        # Reload the table.
        #
        reload: (row_index) ->
            @clear_cache()
            @_row_index = row_index  if row_index isnt undefined
            @table_el.fnDraw false
            return

        #
        # Refresh the table.
        #
        refresh: (value_pair) ->
            @clear_cache()
            @_value_pair = value_pair  if value_pair
            @table_el.fnDraw false
            return

        #
        # Destroy the DataTable and empty the table element..
        #
        destroy: ->

            # Remove any listeners.
            @undelegateEvents()

            if @table_el and $.fn.DataTable.fnIsDataTable(@table_el.get(0))
                console.debug "Destroying DataTable with id: #{@table_el.attr 'id'}'"

                # Close any child views.
                console.debug "Closing #{@container.length} TableView child views..."
                @container.forEach (child) ->
                    if child.close
                        child.close()
                    else if child.remove
                        child.remove
                    else
                        console.warn "Warning: Child view without close or remove function defined: #{child.id}"

                # Destroy the old table.
                @table_el.fnDestroy true

                @trigger "destroy", @table_el

            return

        create_table_el: ->
            table = $ '<table>'
            table.addClass('table').addClass('table-hover').addClass('table-condensed').addClass('table-bordered').addClass('table-striped')

        #
        # Render the table.  If you are obtaining data from a collection then don't invoke this method, call fetch()
        # instead.  If obtaining data via server side ajax then this method can be called with server side parameters.
        #
        # @param params - the server side ajax parameters.  A map keyed by the name server_params.
        #
        #     table.render({server_params: {suppression_id: suppression_id}});
        #
        render: (params) ->
            console.debug "TableView(#{@instanceName}).render()"

            # Clear the cache before re-destroying the table.
            @.clear_cache()

            # Destroy the existing table if there is one.
            @.destroy()

            # Create a table element to attach to.
            @table_el = @create_table_el()
            @$el.append @table_el

            # Keep track of the expanded rows.
            @._expanded_rows = []

            # Construct the table settings based on the supplied settings.
            settings = get_datatables_settings(@, @.options)

            if @collection
                # Loading data using a collection, set aaData to the output.
                settings.aaData = @collection.toJSON()
            else if params and params.server_params isnt null
                # Loading data url call, specify parameters to include in the request.
                server_params = params.server_params
            else if @options.server_params
                # Loading data url call, specify parameters to include in the request.
                server_params = @options.server_params

            if server_params
                # Pass in a fnServerParams function to supply additional request parameters.
                console.debug "Setting server params..."
                settings.fnServerParams = (aoData) ->
                    for key, val of server_params
                        console.debug "Setting param #{key} and value #{val}"
                        aoData.push
                            name: key
                            value: val

            # Create the table.
            @table_el.dataTable(settings)

            @.delegateEvents "click tr i.expand": "on_expand"

            # Assign the bootstrap class to the length select.
            length_selects = @$('.dataTables_wrapper select')
            search_labels = @$('.dataTables_wrapper label')
            for length_select in length_selects
                unless $(length_select).hasClass("form-control")
                    $(length_select).addClass('form-control')
            for label in search_labels
                $(label).css('margin-top', '5px').css('margin-right', '5px')

            search_inputs = @$('.dataTables_filter').find('input')
            for search_input in search_inputs
                $(search_input).css('margin-bottom', '5px')

        on_expand: (ev) ->
            ev.stopPropagation()
            tr = $(ev.currentTarget).closest("tr")
            @trigger "expand", tr.get(0)
            false

        #
        # Fetch the collection or retrieve the server side table data.
        #
        fetch: (params) ->
            view = @

            console.debug "TableView.fetch(#{params})"

            if params
                view.params = params
            else
                view.params = undefined

            if view.collection
                if params
                    # User has supplied options to the fetch call.
                    if not params.success and not params.error

                        # Has not overidden the success and error callbacks, block for them.
                        params.success = =>
                            @render()
                            utils.unblock @$el
                            return

                        params.error = (collection, response) =>
                            utils.unblock @$el
                            utils.display_response_error('Exception while retrieving table data', response)
                            return

                        utils.block_element @$el
                        view.collection.fetch params
                    else
                        # Don't do any blocking.
                        view.collection.fetch params
                else

                    # Block the UI before the fetch.
                    utils.block_element @$el
                    view.collection.fetch
                        success: =>
                            # Unblock the ui.
                            @render()
                            utils.unblock @$el
                            return
                        error: (collection, response) ->
                            utils.unblock @$el
                            utils.display_response_error('Exception while retrieving table data', response)
                            return
            else
                view.render server_params: params

            return

        #
        # Clean up and remove the table.
        #
        onBeforeClose: ->
            @destroy()

            # Fire an event after cleaning up.
            @trigger "close"
            return

        #
        # Update a client row instance.
        # Params:
        #   row_search_key - the name of the row column.
        #   row_search_value - the value to match for the row column.
        #   row_update_key - the name of the row column to update.
        #   row_update_value - the updated column value.
        #   row_column_index - the visible column to updated.  Hidden columns are not applicable.
        #
        update_row: (row_search_key, row_search_value, row_update_key, row_update_value, row_column_index) ->
            view = this

            console.debug "Updating table row for for #{row_search_key}=#{row_search_value} to #{row_update_key}=#{row_update_value} having index: #{row_column_index}"

            nodes = view.get_nodes()
            i = 0

            updated = false
            for node, i in nodes
                data = view.get_data(i)
                if row_search_value is data[row_search_key]

                    # Found the relevant row.
                    data[row_update_key] = row_update_value
                    cols = $(node).children("td")

                    # Update the tagname cell.
                    $(cols[row_column_index]).empty()
                    $(cols[row_column_index]).html row_update_value

                    updated = true
                    break # **EXIT**
                i++
            console.debug "Row updated?: #{updated}"
            return


        #
        # Escape a cells contents.
        #
        escape_cell: (row, index) ->
            col = @get_settings().aoColumns[index]
            td = $("td:eq(#{index})", row)
            td.html _.escape(td.html())  if td
            return


        set_key: (aoData, sKey, mValue) ->
            i = 0
            iLen = aoData.length

            while i < iLen
                aoData[i].value = mValue  if aoData[i].name is sKey
                i++
            return

        get_key: (aoData, sKey) ->
            i = 0
            iLen = aoData.length

            while i < iLen
                return aoData[i].value  if aoData[i].name is sKey
                i++
            null

        #
        # Clear the pipeline cache.
        #
        clear_cache: ->
            if @cache
                @cache = undefined
            return

        #
        # DataTables pipelining support.
        #
        pipeline: (sSource, aoData, fnCallback) ->
            view = this
            ajax_data_prop = view.get_settings().sAjaxDataProp


            if not view.cache
                # Initialize the cache the first time.
                view.cache = {
                    iCacheLower: -1
                }

            # Adjust the pipe size
            bNeedServer = false
            sEcho = view.get_key(aoData, "sEcho")
            iRequestStart = view.get_key(aoData, "iDisplayStart")
            iRequestLength = view.get_key(aoData, "iDisplayLength")
            iRequestEnd = iRequestStart + iRequestLength
            view.cache.iDisplayStart = iRequestStart

            # outside pipeline?
            if view.cache.iCacheLower < 0 or iRequestStart < view.cache.iCacheLower or iRequestEnd > view.cache.iCacheUpper
                bNeedServer = true
            else unless aoData.length is view.cache.lastRequest.length

                # The number of parameters is different between the current request and the last request, assume that
                # going back to the server is necessary.
                bNeedServer = true
            else if view.cache.lastRequest
                i = 0
                iLen = aoData.length

                while i < iLen
                    param = aoData[i]
                    last_param = view.cache.lastRequest[i]
                    is_param_array = Array.isArray(param)
                    is_last_param_array = Array.isArray(last_param)
                    if is_param_array and is_last_param_array

                        # The params are both arrays, compare them.
                        unless param.length is last_param.length

                            # The array lengths don't match, assume the server is needed.
                            bNeedServer = true
                            break # **EXIT**
                        else

                            # Need to compare the actual array contents.
                            param_index = 0

                            while param.length
                                p1 = param[param_index]
                                p2 = last_param[param_index]
                                unless p1.value is p2.value
                                    bNeedServer = true
                                    break # **EXIT**
                                param_index++
                    else if is_param_array and not is_last_param_array or not is_param_array and is_last_param_array

                        # Parameter type mismatch.
                        bNeedServer = true
                        break # **EXIT**
                    else if param.name isnt "iDisplayStart" and param.name isnt "iDisplayLength" and param.name isnt "sEcho"
                        unless param.value is last_param.value
                            bNeedServer = true
                            break # **EXIT**
                    i++

            # Store the request for checking next time around
            view.cache.lastRequest = aoData.slice()
            if bNeedServer
                iPipe = undefined
                if view.options.iPipe and _.isNumber(view.options.iPipe)
                    iPipe = view.options.iPipe
                else
                    iPipe = 10
                if iRequestStart < view.cache.iCacheLower
                    iRequestStart = iRequestStart - (iRequestLength * (iPipe - 1))
                    iRequestStart = 0  if iRequestStart < 0
                view.cache.iCacheLower = iRequestStart
                view.cache.iCacheUpper = iRequestStart + (iRequestLength * iPipe)
                view.cache.iDisplayLength = view.get_key(aoData, "iDisplayLength")
                view.set_key aoData, "iDisplayStart", iRequestStart
                view.set_key aoData, "iDisplayLength", iRequestLength * iPipe

                # Block the UI before the AJAX call.
                utils.block_element @$el

                # Callback processing
                $.getJSON(sSource, aoData,(json) ->
                    view.cache.lastJson = jQuery.extend(true, {}, json)
                    json[ajax_data_prop].splice 0, view.cache.iDisplayStart - view.cache.iCacheLower  unless view.cache.iCacheLower is view.cache.iDisplayStart
                    json[ajax_data_prop].splice view.cache.iDisplayLength, json[ajax_data_prop].length
                    fnCallback json
                    return
                ).always =>
                    # Unblock the UI.
                    utils.unblock @$el
                    @trigger 'sync'
                    return

            else
                try

                # Block the UI before processing.
                    utils.block_element @$el
                    json = jQuery.extend(true, {}, view.cache.lastJson)
                    json.sEcho = sEcho

                    # Update the echo for each response
                    json[ajax_data_prop].splice 0, iRequestStart - view.cache.iCacheLower
                    json[ajax_data_prop].splice iRequestLength, json[ajax_data_prop].length
                    fnCallback json
                finally
                    # Unblock the UI.
                    utils.unblock @$el
            return

        #
        # Date formatter instance.
        #
        date_formatter: (index) ->
            {
                mRender: (data, type, row) ->
                    utils.format_date_string data
                aTargets: [index]
            }

        #
        # Return the list of expanded rows.
        #
        expanded_rows: ->
            @_expanded_rows


        #
        # Expand the contents of a row.
        # @param tr - the row.
        # @param details_callback - function(tr, data) - returns the details HTML.
        #
        expand_collapse_row: (tr, details_callback) ->
            expanded = @expanded_rows()
            index = $.inArray(tr, expanded)
            if index is -1
                expand_icon = $(tr).find("i.expand")
                if expand_icon
                    expand_icon.removeClass "fa-plus-circle"
                    expand_icon.addClass "fa-minus-circle"
                expanded.push tr
                data = @get_data(tr)
                view.get_table().fnOpen tr, details_callback(data), "details"
            else
                collapse_icon = $(tr).find("i.expand")
                if collapse_icon
                    collapse_icon.removeClass "fa-minus-circle"
                    collapse_icon.addClass "fa-plus-circle"
                expanded.splice index, 1
                @table_el.fnClose tr
            return

        #
        # Update the column widths of the table.  Call this function in conjunction with the scroll plugin after the
        # table is displayed to the screen.
        #
        adjust_column_sizing: ->
            if @table_el
                @table_el.fnAdjustColumnSizing()

        #
        # Retrieve the table status data.  Used in conjunction with events.
        #
        get_status_data: ->
            settings = @get_settings()
            display_length = settings.iDisplayLength

            position: @get_selected_position()
            is_prev: @is_prev()
            is_next: @is_next()
            is_prev_page: @is_prev_page()
            is_next_page: @is_next_page()
            display_length: display_length
            length: @length()

        #
        # Handle the clicking of a row.
        #
        on_row_click: (ev) =>
            console.debug 'Handling click of table row...'

            row = ev.currentTarget

            # Select the row.
            @highlight_row(row)

            click_data = @get_data ev.currentTarget

            # Trigger a local click event.
            @trigger "click", click_data, ev

            return

    #
    # Retrieve the default dataTables settings.
    #
    get_datatables_settings = (parent, settings) ->
        defaults =
            iDisplayLength: 10
            aLengthMenu: [
                10
                25
                50
                100
                200
            ]
            sDom: "t"
            bAutoWidth: false
            sPaginationType: 'bs_full'
            bSortClasses: false
            bProcessing: false
            asStripeClasses: []

            fnRowCallback: (row, data, display_index, display_index_full) ->
                parent.trigger 'row:callback', row, data, display_index, display_index_full

                # Unbind any existing click handlers.
                $(row).unbind 'click', parent.on_row_click

                # Bind a click event to the row.
                $(row).bind "click", parent.on_row_click

            fnCreatedRow: (nRow, data, iDataIndex) ->
                parent.trigger "row:created", nRow, data, iDataIndex
                return

            fnInitComplete: (oSettings, json) ->
                parent.trigger "load", oSettings, json
                return

            fnDrawCallback: (oSettings) ->
                parent.trigger "draw", oSettings
                parent.trigger "empty"  if parent.length() is 0
                return

        if settings.iPipe and settings.iPipe > 0
            defaults.fnServerData = (sSource, aoData, fnCallback) ->
                parent.pipeline sSource, aoData, fnCallback
                return


        results = {}

        for k, v of defaults
            results[k] = v

        for k, v of settings
            results[k] = v

        results

    # Mixin events.
    utils.mixin TableView, Evented
