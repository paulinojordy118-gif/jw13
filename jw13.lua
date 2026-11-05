-- ============================================================================
-- JW DUPLICATOR & INVENTORY BACKEND HUB - CAMERAMAN TD EDITION
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- ============================================================================
-- PARTE 1: LÓGICA DEL SERVIDOR (DATASTORE DE TORRES, INVENTARIO Y MONEDAS)
-- ============================================================================
if RunService:IsServer() then
    local DataStoreService = game:GetService("DataStoreService")
    -- DataStore exclusivo para el guardado de Cameraman Tower Defense
    local TDDataStore = DataStoreService:GetDataStore("JW_CameramanTD_SaveSystem_v1")

    local InventoryManager = {}

    -- Generador de identificadores únicos para cada torre/unidad (evita que se apilen)
    function InventoryManager.GenerarUUID()
        local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
        return string.gsub(template, "[xy]", function(c)
            local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
            return string.format("%x", v)
        end)
    end

    -- Estructura de datos por defecto para nuevos jugadores (con unidades base del juego)
    function InventoryManager.ObtenerDatosPorDefecto()
        return {
            Monedas = 500,
            Gemas = 50,
            Unidades = {
                { UniqueID = InventoryManager.GenerarUUID(), Name = "Large Cameraman", Level = 1, Exp = 0 },
                { UniqueID = InventoryManager.GenerarUUID(), Name = "Cameraman", Level = 1, Exp = 0 }
            },
            Equipadas = {"Large Cameraman", "Cameraman"}
        }
    end

    local sesionesJugadores = {}
    local transaccionesBloqueadas = {}

    -- Cargar datos al entrar el jugador usando UpdateAsync (Atómico y Seguro)
    Players.PlayerAdded:Connect(function(player)
        local userId = "Player_" .. player.UserId
        local success, err = pcall(function()
            TDDataStore:UpdateAsync(userId, function(datosActuales)
                if datosActuales == nil then
                    return InventoryManager.ObtenerDatosPorDefecto()
                else
                    return datosActuales
                end
            end)
        end)

        if success then
            local getSuccess, currentData = pcall(function()
                return TDDataStore:GetAsync(userId)
            end)
            if getSuccess and currentData then
                sesionesJugadores[player] = currentData
                print("[JW TD SERVER] Datos de inventario cargados para: " .. player.Name)
            end
        else
            warn("[JW TD SERVER] Error al cargar datos de " .. player.Name .. ": " .. tostring(err))
        end
    end)

    -- Canal de comunicación para sincronizar o duplicar elementos en el backend del juego
    local remotesFolder = ReplicatedStorage:FindFirstChild("JW_Remotes")
    if not remotesFolder then
        remotesFolder = Instance.new("Folder")
        remotesFolder.Name = "JW_Remotes"
        remotesFolder.Parent = ReplicatedStorage
    end

    local tdFunction = remotesFolder:FindFirstChild("TD_ManagerFunction")
    if not tdFunction then
        tdFunction = Instance.new("RemoteFunction")
        tdFunction.Name = "TD_ManagerFunction"
        tdFunction.Parent = remotesFolder
    end

    -- Procesamiento de solicitudes del cliente (como duplicar/guardar unidades en el perfil)
    tdFunction.OnServerInvoke = function(player, accion, targetUniqueID)
        if not sesionesJugadores[player] then
            return false, "Sesión no inicializada."
        end

        if transaccionesBloqueadas[player.UserId] then
            return false, "Operación en proceso..."
        end
        transaccionesBloqueadas[player.UserId] = true

        local datosJugador = sesionesJugadores[player]
        local respuesta = false
        local mensaje = "Acción no reconocida."

        if accion == "DuplicarUnidad" then
            -- Buscar la unidad original por su ID único
            local unidadEncontrada = nil
            for _, u in ipairs(datosJugador.Unidades) do
                if u.UniqueID == targetUniqueID then
                    unidadEncontrada = u
                    break
                end
            end

            if unidadEncontrada then
                -- Crear clon con nuevo UUID y guardarlo en el DataStore
                local clon = {
                    UniqueID = InventoryManager.GenerarUUID(),
                    Name = unidadEncontrada.Name,
                    Level = unidadEncontrada.Level,
                    Exp = unidadEncontrada.Exp,
                    EsDuplicado = true
                }
                table.insert(datosJugador.Unidades, clon)

                -- Guardado persistente atómico
                local userId = "Player_" .. player.UserId
                local saveSuccess = pcall(function()
                    TDDataStore:SetAsync(userId, datosJugador)
                end)

                if saveSuccess then
                    respuesta = true
                    mensaje = "¡Unidad " .. clon.Name .. " duplicada y guardada en DataStore!"
                    print("[JW TD SERVER] " .. player.Name .. " duplicó exitosamente: " .. clon.Name)
                else
                    table.remove(datosJugador.Unidades, #datosJugador.Unidades) -- Revertir si falla
                    mensaje = "Error al guardar en el servidor."
                end
            else
                mensaje = "No se encontró la unidad en tu inventario registrado."
            end
        end

        transaccionesBloqueadas[player.UserId] = nil
        return respuesta, mensaje
    end

    -- Guardado automático al salir
    Players.PlayerRemoving:Connect(function(player)
        local userId = "Player_" .. player.UserId
        local datosJugador = sesionesJugadores[player]
        if datosJugador then
            pcall(function()
                TDDataStore:SetAsync(userId, datosJugador)
            end)
            sesionesJugadores[player] = nil
            print("[JW TD SERVER] Datos guardados al salir para: " .. player.Name)
        end
    end)

-- ============================================================================
-- PARTE 2: LÓGICA DEL CLIENTE (INTERFAZ LIMPIA Y ESCÁNER DE TORRES)
-- ============================================================================
elseif RunService:IsClient() then
    task.spawn(function()
        local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
        local parentGui = CoreGui
        local success, _ = pcall(function() local test = CoreGui.Name end)
        if not success then
            parentGui = PlayerGui
        end

        if parentGui:FindFirstChild("JW_TDHub") then
            parentGui.JW_TDHub:Destroy()
        end

        local ScreenGui = Instance.new("ScreenGui")
        ScreenGui.Name = "JW_TDHub"
        ScreenGui.ResetOnSpawn = false
        ScreenGui.Parent = parentGui

        -- Botón principal JW (Arrastrable)
        local JWBtn = Instance.new("TextButton")
        JWBtn.Name = "JWButton"
        JWBtn.Size = UDim2.new(0, 50, 0, 50)
        JWBtn.Position = UDim2.new(0.02, 0, 0.4, 0)
        JWBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        JWBtn.TextColor3 = Color3.fromRGB(0, 210, 255)
        JWBtn.Text = "JW"
        JWBtn.TextSize = 22
        JWBtn.Font = Enum.Font.SourceSansBold
        JWBtn.BorderSizePixel = 2
        JWBtn.BorderColor3 = Color3.fromRGB(0, 170, 255)
        JWBtn.Active = true
        JWBtn.Draggable = true
        JWBtn.Parent = ScreenGui

        -- Ventana principal del Hub
        local MainFrame = Instance.new("Frame")
        MainFrame.Name = "MainFrame"
        MainFrame.Size = UDim2.new(0, 310, 0, 320)
        MainFrame.Position = UDim2.new(0.02, 60, 0.35, 0)
        MainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
        MainFrame.BorderSizePixel = 2
        MainFrame.BorderColor3 = Color3.fromRGB(0, 170, 255)
        MainFrame.Visible = false
        MainFrame.Parent = ScreenGui

        local Title = Instance.new("TextLabel")
        Title.Size = UDim2.new(1, 0, 0, 30)
        Title.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        Title.TextColor3 = Color3.fromRGB(255, 255, 255)
        Title.Text = "CAMERAMAN TD - JW HUB"
        Title.TextSize = 13
        Title.Font = Enum.Font.SourceSansBold
        Title.Parent = MainFrame

        local ScrollList = Instance.new("ScrollingFrame")
        ScrollList.Size = UDim2.new(0.9, 0, 0.5, 0)
        ScrollList.Position = UDim2.new(0.05, 0, 0.15, 0)
        ScrollList.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        ScrollList.BorderColor3 = Color3.fromRGB(50, 50, 50)
        ScrollList.ScrollBarThickness = 6
        ScrollList.Parent = MainFrame

        local UIListLayout = Instance.new("UIListLayout")
        UIListLayout.Parent = ScrollList
        UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
        UIListLayout.Padding = UDim.new(0, 4)

        local SelectedLabel = Instance.new("TextLabel")
        SelectedLabel.Size = UDim2.new(0.9, 0, 0.08, 0)
        SelectedLabel.Position = UDim2.new(0.05, 0, 0.67, 0)
        SelectedLabel.BackgroundTransparency = 1
        SelectedLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
        SelectedLabel.Text = "Selecciona una torre..."
        SelectedLabel.TextSize = 12
        SelectedLabel.Font = Enum.Font.SourceSans
        SelectedLabel.Parent = MainFrame

        local RefreshBtn = Instance.new("TextButton")
        RefreshBtn.Size = UDim2.new(0.42, 0, 0.12, 0)
        RefreshBtn.Position = UDim2.new(0.05, 0, 0.78, 0)
        RefreshBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        RefreshBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        RefreshBtn.Text = "Actualizar"
        RefreshBtn.TextSize = 13
        RefreshBtn.Font = Enum.Font.SourceSansBold
        RefreshBtn.Parent = MainFrame

        local DupeBtn = Instance.new("TextButton")
        DupeBtn.Size = UDim2.new(0.42, 0, 0.12, 0)
        DupeBtn.Position = UDim2.new(0.53, 0, 0.78, 0)
        DupeBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
        DupeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        DupeBtn.Text = "Duplicate TD"
        DupeBtn.TextSize = 13
        DupeBtn.Font = Enum.Font.SourceSansBold
        DupeBtn.Parent = MainFrame

        local unidadSeleccionADA = nil
        local idUnicoSeleccionado = nil

        -- Escáner enfocado exclusivamente en torres y unidades del juego (Cameraman, Speakerman, etc.)
        local function escanearTorresTD()
            local unidadesEncontradas = {}
            
            -- Clases y nombres basura a ignorar por completo
            local ignorados = {"Humanoid", "BodyColors", "Accessory", "Shirt", "Pants", "Head", "Torso", "Left Arm", "Right Arm", "JW_TDHub"}

            local function registrarObjeto(item)
                if item and item.Name and item.Name ~= "" then
                    local nombre = item.Name
                    local ignorar = false
                    for _, v in ipairs(ignorados) do
                        if nombre == v or item:IsA(v) then ignorar = true end
                    end

                    if not ignorar and not nombre:match("UI") and not nombre:match("Gui") then
                        local uniqueID = item:GetAttribute("UniqueID") or (nombre .. "_" .. math.random(1000, 9999))
                        local yaExiste = false
                        for _, u in ipairs(unidadesEncontradas) do
                            if u.Name == nombre then yaExiste = true end
                        end
                        if not yaExiste then
                            table.insert(unidadesEncontradas, {Name = nombre, ID = uniqueID})
                        end
                    end
                end
            end

            -- Buscar en contenedores típicos de torres y unidades
            local contenedores = {
                LocalPlayer:FindFirstChild("Units"),
                LocalPlayer:FindFirstChild("Inventory"),
                LocalPlayer:FindFirstChild("Towers"),
                LocalPlayer:FindFirstChild("Backpack"),
                ReplicatedStorage:FindFirstChild("Units"),
                ReplicatedStorage:FindFirstChild("Towers")
            }

            for _, cont in ipairs(contenedores) do
                if cont then
                    for _, item in ipairs(cont:GetDescendants()) do
                        registrarObject = registrarObjeto(item)
                    end
                end
            end

            return unidadesEncontradas
        end

        local function cargarListaEnUI()
            for _, item in ipairs(ScrollList:GetChildren()) do
                if item:IsA("TextButton") then
                    item:Destroy()
                end
            end

            local lista = escanearTorresTD()

            for _, info in ipairs(lista) do
                local btnUnidad = Instance.new("TextButton")
                btnUnidad.Size = UDim2.new(1, -6, 0, 30)
                btnUnidad.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
                btnUnidad.TextColor3 = Color3.fromRGB(255, 255, 255)
                btnUnidad.Text = info.Name
                btnUnidad.TextSize = 13
                btnUnidad.Font = Enum.Font.SourceSansSemibold
                btnUnidad.Parent = ScrollList

                btnUnidad.MouseButton1Click:Connect(function()
                    unidadSeleccionADA = info.Name
                    idUnicoSeleccionado = info.ID
                    SelectedLabel.Text = "Torre: " .. info.Name
                    SelectedLabel.TextColor3 = Color3.fromRGB(0, 255, 127)
                end)
            end

            ScrollList.CanvasSize = UDim2.new(0, 0, 0, #lista * 34)
        end

        JWBtn.MouseButton1Click:Connect(function()
            MainFrame.Visible = not MainFrame.Visible
            if MainFrame.Visible then
                cargarListaEnUI()
            end
        end)

        RefreshBtn.MouseButton1Click:Connect(function()
            cargarListaEnUI()
            SelectedLabel.Text = "¡Inventario de torres escaneado!"
            SelectedLabel.TextColor3 = Color3.fromRGB(0, 210, 255)
        end)

        -- Acción del botón Duplicar conectado al DataStore y eventos del juego
        DupeBtn.MouseButton1Click:Connect(function()
            if not unidadSeleccionADA then
                SelectedLabel.Text = "¡Selecciona una torre primero!"
                SelectedLabel.TextColor3 = Color3.fromRGB(255, 70, 70)
                return
            end

            SelectedLabel.Text = "Guardando en DataStore..."
            SelectedLabel.TextColor3 = Color3.fromRGB(255, 215, 0)

            local remotesFolder = ReplicatedStorage:FindFirstChild("JW_Remotes")
            local tdFunction = remotesFolder and remotesFolder:FindFirstChild("TD_ManagerFunction")

            if tdFunction and tdFunction:IsA("RemoteFunction") then
                local success, exitoServer, mensaje = pcall(function()
                    return tdFunction:InvokeServer("DuplicarUnidad", idUnicoSeleccionado)
                end)

                if success and exitoServer then
                    SelectedLabel.Text = "¡Éxito: " .. unidadSeleccionADA .. " guardada!"
                    SelectedLabel.TextColor3 = Color3.fromRGB(0, 255, 127)
                    cargarListaEnUI()
                    return
                else
                    SelectedLabel.Text = mensaje or "Rechazado por el servidor."
                    SelectedLabel.TextColor3 = Color3.fromRGB(255, 70, 70)
                end
            else
                -- Fallback para juegos públicos: Disparar evento remoto de torres si existe
                local disparado = false
                for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
                    if obj:IsA("RemoteEvent") then
                        local n = obj.Name:lower()
                        if n:match("tower") or n:match("unit") or n:match("buy") or n:match("spawn") then
                            pcall(function()
                                obj:FireServer(unidadSeleccionADA)
                                disparado = true
                            end)
                        end
                    end
                end

                if disparado then
                    SelectedLabel.Text = "¡Petición enviada al juego!"
                    SelectedLabel.TextColor3 = Color3.fromRGB(0, 255, 127)
                else
                    SelectedLabel.Text = "No se encontró canal de red."
                    SelectedLabel.TextColor3 = Color3.fromRGB(255, 70, 70)
                end
            end
        end)

        print("[JW TD HUB] Interfaz de Cameraman TD lista.")
    end)
end
