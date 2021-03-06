--===========================================================================--
--                                                                           --
--                       Attribute for ContextHandlers                       --
--                                                                           --
--===========================================================================--

--===========================================================================--
-- Author       :   kurapica125@outlook.com                                  --
-- URL          :   http://github.com/kurapica/PLoop                         --
-- Create Date  :   2018/04/04                                               --
-- Update Date  :   2020/02/21                                               --
-- Version      :   1.3.0                                                    --
--===========================================================================--

PLoop(function(_ENV)
    namespace "System.Web"

    --- The context handler wrapper for text
    __Sealed__() __NoRawSet__(false) __NoNilValue__(false)
    class "__Text__" (function(_ENV)
        extend "IInitAttribute"

        export {
            unpack              = unpack,
            issubtype           = Class.IsSubType,
            HEAD_PHASE          = IHttpContextHandler.ProcessPhase.Head,
            Error               = Logger.Default[Logger.LogLevel.Error],

            IHttpContextHandler, AttributeTargets, __Text__, HTTP_STATUS, Controller
        }

        local processHandler    = function(self, context, phase)
            local response      = context.Response
            if response.RequestRedirected or response.StatusCode ~= HTTP_STATUS.OK then return end

            if phase == HEAD_PHASE then
                local iter, obj, idx    = self[2](context)
                if response.RequestRedirected or response.StatusCode ~= HTTP_STATUS.OK then return end

                if iter then
                    response.ContentType= "text/plain"
                    context[__Text__]   = self[3] and { iter, obj, idx } or iter
                else
                    if self[3] then
                        Error("The function %q failed to return an iterator", self[1])
                    else
                        Error("The function %q failed to return a text value", self[1])
                    end
                    response.StatusCode = HTTP_STATUS.SERVER_ERROR
                end
            else
                local write     = response.Write
                local content   = context[__Text__]
                if content then
                    if self[3] then
                        for idx, text in unpack(content) do
                            write(text or idx)
                        end
                    else
                        write(content)
                    end
                end
            end
        end

        TextContextHandler      = class { IHttpContextHandler,
            Process = processHandler,
            __call  = processHandler,
            __new   = function(_, name, target, async) return { name, target, async }, true end,
        }

        -----------------------------------------------------------
        --                        method                         --
        -----------------------------------------------------------
        --- modify the target's definition
        -- @param   target                      the target
        -- @param   targettype                  the target type
        -- @param   definition                  the target's definition
        -- @param   owner                       the target's owner
        -- @param   name                        the target's name in the owner
        -- @param   stack                       the stack level
        -- @return  definition                  the new definition
        function InitDefinition(self, target, targettype, definition, owner, name, stack)
            if targettype == AttributeTargets.Method and issubtype(owner, Controller) then
                return function (self, ...) return self:Text(definition(self, ...)) end
            elseif targettype == AttributeTargets.Function then
                return TextContextHandler(name, definition, self.Async or false)
            end
        end

        -----------------------------------------------------------
        --                       property                        --
        -----------------------------------------------------------
        --- the attribute target
        property "AttributeTarget"  { set = false, default = AttributeTargets.Function + AttributeTargets.Method }
        property "Priority"         { set = false, default = AttributePriority.Lowest }

        -----------------------------------------------------------
        --                      constructor                      --
        -----------------------------------------------------------
        __Arguments__{ Variable("async", Boolean, true, false) }
        function __ctor(self, async)
            self.Async = async
        end
    end)

    --- The context handler wrapper for json
    __Sealed__() __NoRawSet__(false) __NoNilValue__(false)
    class "__Json__" (function(_ENV)
        extend "IInitAttribute"

        export {
            serialize           = Serialization.Serialize,
            HEAD_PHASE          = IHttpContextHandler.ProcessPhase.Head,
            issubtype           = Class.IsSubType,
            Error               = Logger.Default[Logger.LogLevel.Error],

            IHttpContextHandler, JsonFormatProvider, Controller, AttributeTargets, __Json__, HTTP_STATUS,
        }

        local processHandler    = function(self, context, phase)
            local response      = context.Response
            if response.RequestRedirected or response.StatusCode ~= HTTP_STATUS.OK then return end

            if phase == HEAD_PHASE then
                local data, type= self[2](context)
                if response.RequestRedirected or response.StatusCode ~= HTTP_STATUS.OK then return end

                if data then
                    response.ContentType    = "application/json"
                    if context.IsInnerRequest then -- and context.RawContext.ProcessPhase == HEAD_PHASE then
                        context:SaveJsonData(data, type)
                    else
                        context[__Json__]   = { data, type }
                    end
                else
                    Error("The function %q failed to return a json data", self[1])
                    response.StatusCode     = HTTP_STATUS.SERVER_ERROR
                end
            else
                local content   = context[__Json__]
                if content then
                    if content[2] then
                        serialize(JsonFormatProvider(), content[1], content[2], response.Write)
                    else
                        serialize(JsonFormatProvider(), content[1], response.Write)
                    end
                end
            end
        end

        JsonContextHandler      = class { IHttpContextHandler,
            Process = processHandler,
            __call  = processHandler,
            __new   = function(_, name, target) return { name, target }, true end,
        }

        -----------------------------------------------------------
        --                        method                         --
        -----------------------------------------------------------
        --- modify the target's definition
        -- @param   target                      the target
        -- @param   targettype                  the target type
        -- @param   definition                  the target's definition
        -- @param   owner                       the target's owner
        -- @param   name                        the target's name in the owner
        -- @param   stack                       the stack level
        -- @return  definition                  the new definition
        function InitDefinition(self, target, targettype, definition, owner, name, stack)
            if targettype == AttributeTargets.Method and issubtype(owner, Controller) then
                return function (self, ...) return self:Json(definition(self, ...)) end
            elseif targettype == AttributeTargets.Function then
                return JsonContextHandler(name, definition)
            end
        end

        -----------------------------------------------------------
        --                       property                        --
        -----------------------------------------------------------
        --- the attribute target
        property "AttributeTarget"  { set = false, default = AttributeTargets.Function + AttributeTargets.Method }
        property "Priority"         { set = false, default = AttributePriority.Lowest }
    end)

    __Sealed__() __NoRawSet__(false) __NoNilValue__(false)
    class "__View__" (function(_ENV)
        extend "IInitAttribute"

        export {
            type                = type,
            HEAD_PHASE          = IHttpContextHandler.ProcessPhase.Head,
            isclass             = Class.Validate,
            issubtype           = Class.IsSubType,
            GetResource         = GetResource,
            loadresource        = IO.Resource.IResourceLoader.LoadResource,
            Error               = Logger.Default[Logger.LogLevel.Error],

            IHttpContextHandler, Controller, IHttpOutput, IO.StringReader, AttributeTargets, __View__, HTTP_STATUS, Web
        }

        local processView       = function(self, default, path, data)
            if self.IsFinished then return end

            local typath        = type(path)
            if typath == "table" then
                path, data      = default, path
            elseif typath ~= "string" then
                path, data      = default
            end

            if not path then return self:ServerError() end
            if data and type(data) ~= "table" then data = nil end

            return self:View(path, data)
        end

        local processHandler    = function(self, context, phase)
            local response      = context.Response
            if response.RequestRedirected or response.StatusCode ~= HTTP_STATUS.OK then return end

            if phase == HEAD_PHASE then
                local path, data= self[2](context)
                if response.RequestRedirected or response.StatusCode ~= HTTP_STATUS.OK then return end

                local typath    = type(path)
                if typath == "table" then
                    path, data  = self[3], path
                elseif typath ~= "string" then
                    path, data  = self[3], nil
                end

                if type(data) ~= "table" then
                    data        = nil
                end

                if path then
                    if self[4] and path == self[3] then
                        context[__View__]       = { self[4], data }
                        response.ContentType    = "text/html"
                    else
                        local cls               = path and GetResource(path, context)

                        if cls and issubtype(cls, IHttpOutput) then
                            context[__View__]   = { cls, data }
                            response.ContentType= "text/html"
                        else
                            Error("%s - the view page file can't be found.", self[3])
                            response.StatusCode = HTTP_STATUS.SERVER_ERROR
                        end
                    end
                else
                    Error("The function %q failed to return a view path", self[1])
                    response.StatusCode = HTTP_STATUS.SERVER_ERROR
                end
            else
                local content   = context[__View__]
                if content then
                    local view  = content[1](content[2])

                    view.Context= context
                    view:OnLoad(context)

                    return view:SafeRender(response.Write, "")
                end
            end
        end

        ViewContextHandler      = class { IHttpContextHandler,
            Process = processHandler,
            __call  = processHandler,
            __new   = function(_, name, target, path, viewcls) return { name, target, path, viewcls }, true end,
        }

        -----------------------------------------------------------
        --                        method                         --
        -----------------------------------------------------------
        --- modify the target's definition
        -- @param   target                      the target
        -- @param   targettype                  the target type
        -- @param   definition                  the target's definition
        -- @param   owner                       the target's owner
        -- @param   name                        the target's name in the owner
        -- @param   stack                       the stack level
        -- @return  definition                  the new definition
        function InitDefinition(self, target, targettype, definition, owner, name, stack)
            if targettype == AttributeTargets.Method and issubtype(owner, Controller) then
                if self.Content then
                    if not self.Path then
                        error("the view path must be specified.", stack + 1)
                    end

                    local viewcls
                    local viewpath  = self.Path
                    local viewcont  = self.Content
                    return function(self, ...)
                        if viewcls ==  nil then
                            viewcls = loadresource(viewpath, StringReader(viewcont), self.Context.Application) or false
                            if not viewcls then
                                Error("The context for path - %q can't be parsed as view", viewpath)
                                return self:ServerError()
                            end
                        end

                        return processView(self, viewcls, definition(self, ...))
                    end
                else
                    local dpath = self.Path
                    if dpath then
                        return function (self, ...)
                            return processView(self, dpath, definition(self, ...))
                        end
                    else
                        return function (self, ...)
                            return processView(self, nil, definition(self, ...))
                        end
                    end
                end
            elseif targettype == AttributeTargets.Function then
                local viewcls
                if self.Content then
                    if not self.Path then
                        error("the view path must be specified.", stack + 1)
                    end

                    viewcls = loadresource(self.Path, StringReader(self.Content), owner)
                    if not (viewcls and issubtype(viewcls, IHttpOutput)) then
                        error("the context can't be parsed as view.", stack + 1)
                    end
                end

                return ViewContextHandler(name, definition, self.Path or false, viewcls or false)
            end
        end

        -----------------------------------------------------------
        --                       property                        --
        -----------------------------------------------------------
        --- the attribute target
        property "AttributeTarget"  { set = false, default = AttributeTargets.Function + AttributeTargets.Method }
        property "Priority"         { set = false, default = AttributePriority.Lowest }

        -----------------------------------------------------------
        --                      constructor                      --
        -----------------------------------------------------------
        __Arguments__{ NEString/nil, NEString/nil }
        function __ctor(self, path, content)
            self.Path       = path
            self.Content    = content
        end

        -----------------------------------------------------------
        --                      meta-method                      --
        -----------------------------------------------------------
        __Arguments__{ NEString }
        function __call(self, content)
            self.Content    = content
        end
    end)

    __Sealed__() __NoRawSet__(false) __NoNilValue__(false)
    class "__Switch__" (function(_ENV)
        extend "IInitAttribute"

        export {
            serialize           = Serialization.Serialize,
            type                = type,
            HEAD_PHASE          = IHttpContextHandler.ProcessPhase.Head,
            isclass             = Class.Validate,
            issubtype           = Class.IsSubType,
            GetResource         = GetResource,
            loadresource        = IO.Resource.IResourceLoader.LoadResource,
            Error               = Logger.Default[Logger.LogLevel.Error],
            Json                = Json,

            SWITCH_CASE_VIEW    = 1,
            SWITCH_CASE_JSON    = 2,
            SWITCH_CASE_TEXT    = 3,

            JsonFormatProvider, IHttpContextHandler, Controller, IHttpOutput, IO.StringReader, AttributeTargets, __Switch__, HTTP_STATUS, Web
        }

        local processView       = function(self, default, path, data)
            if self.IsFinished then return end

            local typath        = type(path)
            if typath == "table" then
                path, data      = default, path
            elseif typath ~= "string" then
                path, data      = default
            end

            if data and type(data) ~= "table" then data = nil end

            return self:AutoSwitch(path, data)
        end

        local processHandler    = function(self, context, phase)
            local response      = context.Response
            if response.RequestRedirected or response.StatusCode ~= HTTP_STATUS.OK then return end

            if phase == HEAD_PHASE then
                local path, data= self[2](context)
                if response.RequestRedirected or response.StatusCode ~= HTTP_STATUS.OK then return end

                local typath    = type(path)
                if typath == "table" then
                    path, data  = self[3], path
                elseif typath ~= "string" then
                    path, data  = self[3], nil
                end

                if type(data) ~= "table" then
                    data        = nil
                end

                local request   = context.Request

                if request:IsHtmlAccepted() then
                    if path then
                        if self[4] and path == self[3] then
                            context[__Switch__]     = { SWITCH_CASE_VIEW, self[4], data }
                            response.ContentType    = "text/html"
                        else
                            local cls               = path and GetResource(path, context)

                            if cls and issubtype(cls, IHttpOutput) then
                                context[__Switch__] = { SWITCH_CASE_VIEW, cls, data }
                                response.ContentType= "text/html"
                            else
                                Error("%s - the view page file can't be found.", self[3])
                                response.StatusCode = HTTP_STATUS.SERVER_ERROR
                            end
                        end
                    else
                        Error("The function %q failed to return a view path", self[1])
                        response.StatusCode         = HTTP_STATUS.SERVER_ERROR
                    end
                elseif request:IsJsonAccepted() then
                    if data then
                        response.ContentType        = "application/json"
                        if context.IsInnerRequest then
                            context:SaveJsonData(data)
                        else
                            context[__Switch__]     = { SWITCH_CASE_JSON, data }
                        end
                    else
                        Error("The function %q failed to return a json data", self[1])
                        response.StatusCode         = HTTP_STATUS.SERVER_ERROR
                    end
                elseif request:IsTextAccepted() then
                    if data then
                        response.ContentType        = "text/plain"
                        context[__Switch__]         = { SWITCH_CASE_TEXT, data }
                    else
                        Error("The function %q failed to return a value as text", self[1])
                        response.StatusCode         = HTTP_STATUS.SERVER_ERROR
                    end
                else
                    response.StatusCode             = HTTP_STATUS.NONE_ACCEPTABLE
                end
            else
                local content                       = context[__Switch__]
                if content then
                    if content[1] == SWITCH_CASE_VIEW then
                        local view                  = content[2](content[3])

                        view.Context                = context
                        view:OnLoad(context)

                        return view:SafeRender(response.Write, "")
                    else
                        serialize(JsonFormatProvider(), content[2], response.Write)
                    end
                end
            end
        end

        ViewContextHandler      = class { IHttpContextHandler,
            Process = processHandler,
            __call  = processHandler,
            __new   = function(_, name, target, path, viewcls) return { name, target, path, viewcls }, true end,
        }

        -----------------------------------------------------------
        --                        method                         --
        -----------------------------------------------------------
        --- modify the target's definition
        -- @param   target                      the target
        -- @param   targettype                  the target type
        -- @param   definition                  the target's definition
        -- @param   owner                       the target's owner
        -- @param   name                        the target's name in the owner
        -- @param   stack                       the stack level
        -- @return  definition                  the new definition
        function InitDefinition(self, target, targettype, definition, owner, name, stack)
            if targettype == AttributeTargets.Method and issubtype(owner, Controller) then
                if self.Content then
                    if not self.Path then
                        error("the view path must be specified.", stack + 1)
                    end

                    local viewcls
                    local viewpath  = self.Path
                    local viewcont  = self.Content
                    return function(self, ...)
                        if viewcls ==  nil then
                            viewcls = loadresource(viewpath, StringReader(viewcont), self.Context.Application) or false
                            if not viewcls then
                                Error("The context for path - %q can't be parsed as view", viewpath)
                                return self:ServerError()
                            end
                        end

                        return processView(self, viewcls, definition(self, ...))
                    end
                else
                    local dpath = self.Path
                    if dpath then
                        return function (self, ...)
                            return processView(self, dpath, definition(self, ...))
                        end
                    else
                        return function (self, ...)
                            return processView(self, nil, definition(self, ...))
                        end
                    end
                end
            elseif targettype == AttributeTargets.Function then
                local viewcls
                if self.Content then
                    if not self.Path then
                        error("the view path must be specified.", stack + 1)
                    end

                    viewcls = loadresource(self.Path, StringReader(self.Content), owner)
                    if not (viewcls and issubtype(viewcls, IHttpOutput)) then
                        error("the context can't be parsed as view.", stack + 1)
                    end
                end

                return ViewContextHandler(name, definition, self.Path or false, viewcls or false)
            end
        end

        -----------------------------------------------------------
        --                       property                        --
        -----------------------------------------------------------
        --- the attribute target
        property "AttributeTarget"  { set = false, default = AttributeTargets.Function + AttributeTargets.Method }
        property "Priority"         { set = false, default = AttributePriority.Lowest }

        -----------------------------------------------------------
        --                      constructor                      --
        -----------------------------------------------------------
        __Arguments__{ NEString/nil, NEString/nil }
        function __ctor(self, path, content)
            self.Path       = path
            self.Content    = content
        end

        -----------------------------------------------------------
        --                      meta-method                      --
        -----------------------------------------------------------
        __Arguments__{ NEString }
        function __call(self, content)
            self.Content    = content
        end
    end)

    __Sealed__() __NoRawSet__(false) __NoNilValue__(false)
    class "__Redirect__" (function(_ENV)
        extend "IInitAttribute"

        export {
            unpack              = unpack,
            issubtype           = Class.IsSubType,
            HEAD_PHASE          = IHttpContextHandler.ProcessPhase.Head,
            Error               = Logger.Default[Logger.LogLevel.Error],

            IHttpContextHandler, AttributeTargets, __Text__, HTTP_STATUS, Controller
        }

        local processHandler    = function(self, context, phase)
            local response      = context.Response
            if response.RequestRedirected then return end

            if phase == HEAD_PHASE then
                local path, raw = self[1](context)
                if path then
                    response:Redirect(path, nil, raw)
                elseif self[2] then
                    response:Redirect(self[2], nil, self[3])
                else
                    response.StatusCode = HTTP_STATUS.NOT_FOUND
                end
            end
        end

        RedirectContextHandler  = class { IHttpContextHandler,
            Process = processHandler,
            __call  = processHandler,
            __new   = function(_, target, path, raw) return { target, path, raw }, true end,
        }

        -----------------------------------------------------------
        --                        method                         --
        -----------------------------------------------------------
        --- modify the target's definition
        -- @param   target                      the target
        -- @param   targettype                  the target type
        -- @param   definition                  the target's definition
        -- @param   owner                       the target's owner
        -- @param   name                        the target's name in the owner
        -- @param   stack                       the stack level
        -- @return  definition                  the new definition
        function InitDefinition(self, target, targettype, definition, owner, name, stack)
            if targettype == AttributeTargets.Method and issubtype(owner, Controller) then
                if self.Path then
                    local opath, oraw       = self.Path, self.Raw
                    return function(self, ...)
                        local path, raw     = definition(self, ...)
                        if path then
                            return self:Redirect(path, raw)
                        else
                            return self:Redirect(opath, oraw)
                        end
                    end
                else
                    return function (self, ...) return self:Redirect(definition(self, ...)) end
                end
            elseif targettype == AttributeTargets.Function then
                return RedirectContextHandler(definition, self.Path, self.Raw)
            end
        end

        -----------------------------------------------------------
        --                       property                        --
        -----------------------------------------------------------
        --- the attribute target
        property "AttributeTarget"  { set = false, default = AttributeTargets.Function + AttributeTargets.Method }
        property "Priority"         { set = false, default = AttributePriority.Lowest }

        -----------------------------------------------------------
        --                      constructor                      --
        -----------------------------------------------------------
        __Arguments__{ NEString/nil, Boolean/nil }
        function __ctor(self, path, raw)
            self.Path       = path
            self.Raw        = raw
        end
    end)
end)