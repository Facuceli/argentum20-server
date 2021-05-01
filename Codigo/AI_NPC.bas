Attribute VB_Name = "AI"
Option Explicit

' WyroX: Hardcodeada de la vida...
Public Const FUEGOFATUO      As Integer = 964

'Damos a los NPCs el mismo rango de visión que un PJ
Public Const RANGO_VISION_X  As Byte = 11
Public Const RANGO_VISION_Y  As Byte = 9


Public Sub NpcAI(ByVal NpcIndex As Integer)
    On Error GoTo ErrorHandler

    With NpcList(NpcIndex)
        Select Case .Movement
            Case TipoAI.Estatico
                ' Es un NPC estatico, no hace nada.
                Exit Sub

            Case TipoAI.MueveAlAzar
                If .Hostile = 1 Then
                    Call PerseguirUsuarioCercano(NpcIndex)
                Else
                    Call AI_CaminarSinRumbo(NpcIndex)
                End If

            Case TipoAI.NpcDefensa
                Call SeguirAgresor(NpcIndex)

            Case TipoAI.NpcAtacaNpc
                Call AI_NpcAtacaNpc(NpcIndex)

            Case TipoAI.SigueAmo
                Call SeguirAmo(NpcIndex)

            Case TipoAI.Caminata
                Call HacerCaminata(NpcIndex)

            Case TipoAI.Invasion
                Call MovimientoInvasion(NpcIndex)

        End Select

    End With

    Exit Sub

ErrorHandler:
    
    Call LogError("NPC.AI " & NpcList(NpcIndex).name & " " & NpcList(NpcIndex).MaestroNPC & " mapa:" & NpcList(NpcIndex).Pos.Map & " x:" & NpcList(NpcIndex).Pos.X & " y:" & NpcList(NpcIndex).Pos.Y & " Mov:" & NpcList(NpcIndex).Movement & " TargU:" & NpcList(NpcIndex).Target & " TargN:" & NpcList(NpcIndex).TargetNPC)

    Dim MiNPC As npc: MiNPC = NpcList(NpcIndex)
    
    Call QuitarNPC(NpcIndex)
    Call ReSpawnNpc(MiNPC)

End Sub

Private Sub PerseguirUsuarioCercano(ByVal NpcIndex As Integer)
    On Error GoTo ErrorHandler

    Dim i            As Long
    Dim UserIndex    As Integer
    Dim npcEraPasivo As Boolean
    Dim agresor      As Integer
    Dim minDistancia As Integer
    Dim minDistanciaAtacable As Integer
    Dim enemigoCercano As Integer
    Dim enemigoAtacableMasCercano As Integer
    
    ' Numero muy grande para que siempre haya un mínimo
    minDistancia = 32000
    minDistanciaAtacable = 32000

    With NpcList(NpcIndex)
        npcEraPasivo = .flags.OldHostil = 0
        .Target = 0
        .TargetNPC = 0

        If .flags.AttackedBy <> vbNullString Then
          agresor = NameIndex(.flags.AttackedBy)
        End If

        ' Busco algun objetivo en el area.
        For i = 1 To ModAreas.ConnGroups(.Pos.Map).CountEntrys
            UserIndex = ModAreas.ConnGroups(.Pos.Map).UserEntrys(i)

            If EsObjetivoValido(NpcIndex, UserIndex) Then

                ' Busco el mas cercano, sea atacable o no.
                If Distancia(UserList(UserIndex).Pos, .Pos) < minDistancia Then
                    enemigoCercano = UserIndex
                    minDistancia = Distancia(UserList(UserIndex).Pos, .Pos)
                End If

                ' Busco el mas cercano que sea atacable.
                If (UsuarioAtacableConMagia(UserIndex) Or UsuarioAtacableConMelee(NpcIndex, UserIndex)) And Distancia(UserList(UserIndex).Pos, .Pos) < minDistanciaAtacable Then
                    enemigoAtacableMasCercano = UserIndex
                    minDistanciaAtacable = Distancia(UserList(UserIndex).Pos, .Pos)
                End If

            End If

        Next i

        ' Al terminar el `for`, puedo tener un maximo de tres objetivos distintos.
        ' Por prioridad, vamos a decidir estas cosas en orden.

        If npcEraPasivo Then
            ' Significa que alguien le pego, y esta en modo agresivo trantando de darle.
            ' El unico objetivo que importa aca es el atacante; los demas son ignorados.
            If EnRangoVision(NpcIndex, agresor) Then .Target = agresor

        Else ' El NPC es hostil siempre, le quiere pegar a alguien.

            If minDistanciaAtacable > 0 And enemigoAtacableMasCercano > 0 Then ' Hay alguien atacable cerca
                .Target = enemigoAtacableMasCercano
            ElseIf enemigoCercano > 0 Then ' Hay alguien cerca, pero no es atacable
                .Target = enemigoCercano
            End If

        End If

        ' Si el NPC tiene un objetivo
        If .Target > 0 Then
            Call AI_AtacarUsuarioObjetivo(NpcIndex)
        Else
            Call RestoreOldMovement(NpcIndex)
            ' No encontro a nadie cerca, camina unos pasos en cualquier direccion.
            Call AI_CaminarSinRumbo(NpcIndex)
        End If

    End With

    Exit Sub

ErrorHandler:
    Call RegistrarError(Err.Number, Err.Description, "AI_NPC.PerseguirUsuarioCercano", Erl)

End Sub

' Cuando un NPC no tiene target y se tiene que mover libremente
Private Sub AI_CaminarSinRumbo(ByVal NpcIndex As Integer)
    With NpcList(NpcIndex)
        If RandomNumber(1, 6) = 3 And .flags.Paralizado = 0 And .flags.Inmovilizado = 0 Then
            Call MoveNPCChar(NpcIndex, CByte(RandomNumber(eHeading.NORTH, eHeading.WEST)))
        Else
            Call AnimacionIdle(NpcIndex, True)
        End If
    End With
End Sub

Private Sub AI_CaminarConRumbo(ByVal NpcIndex As Integer, ByRef rumbo As WorldPos)
    On Error GoTo AI_CaminarConRumbo_Err
    
    If NpcList(NpcIndex).flags.Paralizado Or NpcList(NpcIndex).flags.Inmovilizado Then
        Call AnimacionIdle(NpcIndex, True)
        Exit Sub
    End If
    
    With NpcList(NpcIndex).pathFindingInfo
        ' Si no tiene un camino calculado o si el destino cambio
        If .PathLength = 0 Or .Destination.X <> rumbo.X Or .Destination.Y <> rumbo.Y Then
            .Destination.X = rumbo.X
            .Destination.Y = rumbo.Y

            ' Recalculamos el camino
            If SeekPath(NpcIndex, True) Then
                ' Si consiguió un camino
                Call FollowPath(NpcIndex)
            End If
        Else ' Avanzamos en el camino
            Call FollowPath(NpcIndex)
        End If

    End With

    Exit Sub

AI_CaminarConRumbo_Err:

    Call RegistrarError(Err.Number, Err.Description, "AI.AI_CaminarConRumbo", Erl)
End Sub


Private Sub AI_AtacarUsuarioObjetivo(ByVal AtackerNpcIndex As Integer)
    On Error GoTo ErrorHandler

    Dim AtacaConMagia As Boolean
    Dim AtacaMelee As Boolean
    Dim EstaPegadoAlUsuario As Boolean
    Dim tHeading As Byte
    
    With NpcList(AtackerNpcIndex)
        If .Target = 0 Then Exit Sub
        
        EstaPegadoAlUsuario = (Distancia(.Pos, UserList(.Target).Pos) <= 1)
        AtacaConMagia = (.flags.LanzaSpells And IntervaloPermiteLanzarHechizo(AtackerNpcIndex) And (RandomNumber(1, 100) <= 50 Or Not EstaPegadoAlUsuario))
        AtacaMelee = (EstaPegadoAlUsuario And UsuarioAtacableConMelee(AtackerNpcIndex, .Target) And .flags.Paralizado = 0 And Not AtacaConMagia)

        If AtacaConMagia Then
            ' Le lanzo un Hechizo
            Call NpcLanzaUnSpell(AtackerNpcIndex)
        ElseIf AtacaMelee Then
            ' Se da vuelta y enfrenta al Usuario
            tHeading = GetHeadingFromWorldPos(.Pos, UserList(.Target).Pos)
            Call AnimacionIdle(AtackerNpcIndex, True)
            Call ChangeNPCChar(AtackerNpcIndex, .Char.Body, .Char.Head, tHeading)

            ' Le pego al Usuario
            Call NpcAtacaUser(AtackerNpcIndex, .Target, tHeading)
        End If

        If UsuarioAtacableConMagia(.Target) Or UsuarioAtacableConMelee(AtackerNpcIndex, .Target) Then
            ' Si no tiene un camino pero esta pegado al usuario, no queremos gastar tiempo calculando caminos.
            If .pathFindingInfo.PathLength = 0 And EstaPegadoAlUsuario Then Exit Sub
            
            Call AI_CaminarConRumbo(AtackerNpcIndex, UserList(.Target).Pos)
        End If
    End With

    Exit Sub

ErrorHandler:

    Call RegistrarError(Err.Number, Err.Description, "AIv2.AI_AtacarUsuarioObjetivo", Erl)

End Sub

Public Sub AI_NpcAtacaNpc(ByVal NpcIndex As Integer)
    On Error GoTo ErrorHandler
    
    Dim targetPos As WorldPos
    
    With NpcList(NpcIndex)
        If .TargetNPC > 0 Then
            targetPos = NpcList(.TargetNPC).Pos
            
            If InRangoVisionNPC(NpcIndex, targetPos.X, targetPos.Y) Then
               ' Me fijo si el NPC esta al lado del Objetivo
               If Distancia(.Pos, targetPos) = 1 And .flags.Paralizado = 0 Then
                   Call SistemaCombate.NpcAtacaNpc(NpcIndex, .TargetNPC)
               End If
               
               If .TargetNPC <> vbNull And .TargetNPC > 0 Then
                   Call AI_CaminarConRumbo(NpcIndex, targetPos)
               End If
               
               Exit Sub
            End If
        End If
           
        Call RestoreOldMovement(NpcIndex)
 
    End With

ErrorHandler:

    Call RegistrarError(Err.Number, Err.Description, "AIv2.AI_NpcAtacaNpc", Erl)
End Sub

Private Sub SeguirAgresor(ByVal NpcIndex As Integer)
    ' La IA que se ejecuta cuando alguien le pega al maestro de una Mascota/Elemental
    ' o si atacas a los NPCs con Movement = TIPOAI.NpcDefensa
    ' A diferencia de IrUsuarioCercano(), aca no buscamos objetivos cercanos en el area
    ' porque ya establecemos como objetivo a el usuario que ataco a los NPC con este tipo de IA

    If EsObjetivoValido(NpcIndex, NpcList(NpcIndex).Target) Then
        Call AI_AtacarUsuarioObjetivo(NpcIndex)
    Else
        Call RestoreOldMovement(NpcIndex)
    End If

End Sub

Public Sub SeguirAmo(ByVal NpcIndex As Integer)
    On Error GoTo ErrorHandler
        
    With NpcList(NpcIndex)
        
        If .MaestroUser = 0 Or Not .flags.Follow Then Exit Sub
        
        ' Si la mascota no tiene objetivo establecido.
        If .Target = 0 And .TargetNPC = 0 Then
            
            If EnRangoVision(NpcIndex, .MaestroUser) Then
                If UserList(.MaestroUser).flags.Muerto = 0 And _
                    UserList(.MaestroUser).flags.invisible = 0 And _
                    UserList(.MaestroUser).flags.Oculto = 0 And _
                    Distancia(.Pos, UserList(.MaestroUser).Pos) > 3 Then
                    
                    ' Caminamos cerca del usuario
                    Call AI_CaminarConRumbo(NpcIndex, UserList(.MaestroUser).Pos)
                    Exit Sub
                    
                End If
            End If
                
            Call AI_CaminarSinRumbo(NpcIndex)
        End If
    End With
    
    Exit Sub

ErrorHandler:

    Call RegistrarError(Err.Number, Err.Description, "AIv2.SeguirAmo", Erl)
End Sub

Private Sub RestoreOldMovement(ByVal NpcIndex As Integer)

    With NpcList(NpcIndex)
        .Target = 0
        .TargetNPC = 0
        
        ' Si el NPC no tiene maestro, reseteamos el movimiento que tenia antes.
        If .MaestroUser = 0 Then
            .Movement = .flags.OldMovement
            .Hostile = .flags.OldHostil
            .flags.AttackedBy = vbNullString
        Else
            
            ' Si tiene maestro, hacemos que lo siga.
            Call FollowAmo(NpcIndex)
            
        End If

    End With

End Sub

Private Sub HacerCaminata(ByVal NpcIndex As Integer)
    On Error GoTo Handler
    
    Dim Destino As WorldPos
    Dim Heading As eHeading
    Dim NextTile As WorldPos
    Dim MoveChar As Integer
    Dim PudoMover As Boolean

    With NpcList(NpcIndex)
    
        Destino.Map = .Pos.Map
        Destino.X = .Orig.X + .Caminata(.CaminataActual).Offset.X
        Destino.Y = .Orig.Y + .Caminata(.CaminataActual).Offset.Y

        ' Si todavía no llegó al destino
        If .Pos.X <> Destino.X Or .Pos.Y <> Destino.Y Then
        
            ' Tratamos de acercarnos (podemos pisar npcs, usuarios o triggers)
            Heading = GetHeadingFromWorldPos(.Pos, Destino)
            
            ' Obtengo la posición según el heading
            NextTile = .Pos
            Call HeadtoPos(Heading, NextTile)
            
            ' Si hay un NPC
            MoveChar = MapData(NextTile.Map, NextTile.X, NextTile.Y).NpcIndex
            If MoveChar Then
                ' Lo movemos hacia un lado
                Call MoveNpcToSide(MoveChar, Heading)
            End If
            
            ' Si hay un user
            MoveChar = MapData(NextTile.Map, NextTile.X, NextTile.Y).UserIndex
            If MoveChar Then
                ' Si no está muerto o es admin invisible (porque a esos los atraviesa)
                If UserList(MoveChar).flags.AdminInvisible = 0 Or UserList(MoveChar).flags.Muerto = 0 Then
                    ' Lo movemos hacia un lado
                    Call MoveUserToSide(MoveChar, Heading)
                End If
            End If
            
            ' Movemos al NPC de la caminata
            PudoMover = MoveNPCChar(NpcIndex, Heading)
            
            ' Si no pudimos moverlo, hacemos como si hubiese llegado a destino... para evitar que se quede atascado
            If Not PudoMover Or Distancia(.Pos, Destino) = 0 Then
            
                ' Llegamos a destino, ahora esperamos el tiempo necesario para continuar
                .Contadores.IntervaloMovimiento = GetTickCount + .Caminata(.CaminataActual).Espera - .IntervaloMovimiento
                
                ' Pasamos a la siguiente caminata
                .CaminataActual = .CaminataActual + 1
                
                ' Si pasamos el último, volvemos al primero
                If .CaminataActual > UBound(.Caminata) Then
                    .CaminataActual = 1
                End If
                
            End If
            
        ' Si por alguna razón estamos en el destino, seguimos con la siguiente caminata
        Else
        
            .CaminataActual = .CaminataActual + 1
            
            ' Si pasamos el último, volvemos al primero
            If .CaminataActual > UBound(.Caminata) Then
                .CaminataActual = 1
            End If
            
        End If
    
    End With
    
    Exit Sub
    
Handler:
    Call RegistrarError(Err.Number, Err.Description, "AI.HacerCaminata", Erl)
    Resume Next
End Sub

Private Sub MovimientoInvasion(ByVal NpcIndex As Integer)
    On Error GoTo Handler
    
    With NpcList(NpcIndex)
        Dim SpawnBox As tSpawnBox
        SpawnBox = Invasiones(.flags.InvasionIndex).SpawnBoxes(.flags.SpawnBox)
    
        ' Calculamos la distancia a la muralla y generamos una posición de destino
        Dim DistanciaMuralla As Integer, Destino As WorldPos
        Destino = .Pos
        
        If SpawnBox.Heading = eHeading.EAST Or SpawnBox.Heading = eHeading.WEST Then
            DistanciaMuralla = Abs(.Pos.X - SpawnBox.CoordMuralla)
            Destino.X = SpawnBox.CoordMuralla
        Else
            DistanciaMuralla = Abs(.Pos.Y - SpawnBox.CoordMuralla)
            Destino.Y = SpawnBox.CoordMuralla
        End If

        ' Si todavía está lejos de la muralla
        If DistanciaMuralla > 1 Then
        
            ' Tratamos de acercarnos (sin pisar)
            Dim Heading As eHeading
            Heading = GetHeadingFromWorldPos(.Pos, Destino)
            
            ' Nos aseguramos que la posición nueva está dentro del rectángulo válido
            Dim NextTile As WorldPos
            NextTile = .Pos
            Call HeadtoPos(Heading, NextTile)
            
            ' Si la posición nueva queda fuera del rectángulo válido
            If Not InsideRectangle(SpawnBox.LegalBox, NextTile.X, NextTile.Y) Then
                ' Invertimos la dirección de movimiento
                Heading = InvertHeading(Heading)
            End If
            
            ' Movemos el NPC
            Call MoveNPCChar(NpcIndex, Heading)
        
        ' Si está pegado a la muralla
        Else
        
            ' Chequeamos el intervalo de ataque
            If Not IntervaloPermiteAtacarNPC(NpcIndex) Then
                Exit Sub
            End If
            
            ' Nos aseguramos que mire hacia la muralla
            If .Char.Heading <> SpawnBox.Heading Then
                Call ChangeNPCChar(NpcIndex, .Char.Body, .Char.Head, SpawnBox.Heading)
            End If
            
            ' Sonido de ataque (si tiene)
            If .flags.Snd1 > 0 Then
                Call SendData(SendTarget.ToNPCArea, NpcIndex, PrepareMessagePlayWave(.flags.Snd1, .Pos.X, .Pos.Y))
            End If
            
            ' Sonido de impacto
            Call SendData(SendTarget.ToNPCArea, NpcIndex, PrepareMessagePlayWave(SND_IMPACTO, .Pos.X, .Pos.Y))
            
            ' Dañamos la muralla
            Call HacerDañoMuralla(.flags.InvasionIndex, RandomNumber(.Stats.MinHIT, .Stats.MaxHit))  ' TODO: Defensa de la muralla? No hace falta creo...

        End If
    
    End With

    Exit Sub
    
Handler:
    Call RegistrarError(Err.Number, Err.Description, "AI.MovimientoInvasion", Erl)
    Resume Next
End Sub

' El NPC elige un hechizo al azar dentro de su listado, con un potencial Target.
' Depdendiendo el tipo de spell que elije, se elije un target distinto que puede ser:
' - El .Target, el NPC mismo o area.
Private Sub NpcLanzaUnSpell(ByVal NpcIndex As Integer)
    On Error GoTo NpcLanzaUnSpell_Err
    ' Elegir hechizo, dependiendo del hechizo lo tiro sobre NPC, sobre Target o Sobre area (cerca de user o NPC si no tiene)
    Dim SpellIndex As Integer
    Dim Target As Integer
    Dim PuedeDañarAlUsuario As Boolean

    If Not IntervaloPermiteLanzarHechizo(NpcIndex) Then Exit Sub

    Target = NpcList(NpcIndex).Target
    SpellIndex = NpcList(NpcIndex).Spells(RandomNumber(1, NpcList(NpcIndex).flags.LanzaSpells))
    PuedeDañarAlUsuario = UserList(Target).flags.NoMagiaEfecto = 0 And NpcList(NpcIndex).flags.Paralizado = 0
    
    
    Select Case Hechizos(SpellIndex).Target
      Case TargetType.uUsuarios

        If UsuarioAtacableConMagia(Target) And PuedeDañarAlUsuario Then
          Call NpcLanzaSpellSobreUser(NpcIndex, Target, SpellIndex)

          If UserList(Target).flags.AtacadoPorNpc = 0 Then
            UserList(Target).flags.AtacadoPorNpc = NpcIndex
          End If
        End If

      Case TargetType.uNPC
        If Hechizos(SpellIndex).AutoLanzar = 1 Then
          Call NpcLanzaSpellSobreNpc(NpcIndex, NpcIndex, SpellIndex)

        ElseIf NpcList(NpcIndex).TargetNPC > 0 Then
          Call NpcLanzaSpellSobreNpc(NpcIndex, NpcList(NpcIndex).TargetNPC, SpellIndex)
        End If

      Case TargetType.uUsuariosYnpc
        If Hechizos(SpellIndex).AutoLanzar = 1 Then
          Call NpcLanzaSpellSobreNpc(NpcIndex, NpcIndex, SpellIndex)

        ElseIf UsuarioAtacableConMagia(Target) And PuedeDañarAlUsuario Then
          Call NpcLanzaSpellSobreUser(NpcIndex, Target, SpellIndex)

          If UserList(Target).flags.AtacadoPorNpc = 0 Then
            UserList(Target).flags.AtacadoPorNpc = NpcIndex
          End If

        ElseIf NpcList(NpcIndex).TargetNPC > 0 Then
          Call NpcLanzaSpellSobreNpc(NpcIndex, NpcList(NpcIndex).TargetNPC, SpellIndex)

        End If

      Case TargetType.uTerreno
        Call NpcLanzaSpellSobreArea(NpcIndex, SpellIndex)

    End Select

    Exit Sub

NpcLanzaUnSpell_Err:
    Call RegistrarError(Err.Number, Err.Description, "AI.NpcLanzaUnSpell", Erl)

    Resume Next

End Sub

Private Sub NpcLanzaUnSpellSobreNpc(ByVal NpcIndex As Integer, ByVal TargetNPC As Integer)
    On Error GoTo NpcLanzaUnSpellSobreNpc_Err
    
    With NpcList(NpcIndex)
        
        If Not IntervaloPermiteLanzarHechizo(NpcIndex) Then Exit Sub
        If .Pos.Map <> NpcList(TargetNPC).Pos.Map Then Exit Sub
    
        Dim K As Integer
            K = RandomNumber(1, .flags.LanzaSpells)

        Call NpcLanzaSpellSobreNpc(NpcIndex, TargetNPC, .Spells(K))
    
    End With
     
    Exit Sub

NpcLanzaUnSpellSobreNpc_Err:
    Call RegistrarError(Err.Number, Err.Description, "AI.NpcLanzaUnSpellSobreNpc", Erl)
    Resume Next

End Sub



' ---------------------------------------------------------------------------------------------------
'                                       HELPERS
' ---------------------------------------------------------------------------------------------------

Private Function EsObjetivoValido(ByVal NpcIndex As Integer, ByVal UserIndex As Integer) As Boolean
    If UserIndex = 0 Then Exit Function

    ' Esta condicion debe ejecutarse independiemente de el modo de busqueda.
    EsObjetivoValido = ( _
      EnRangoVision(NpcIndex, UserIndex) And _
      EsEnemigo(NpcIndex, UserIndex) And _
      UserList(UserIndex).flags.Muerto = 0 And _
      UserList(UserIndex).flags.EnConsulta = 0 And _
      Not EsGM(UserIndex))

End Function

Private Function EsEnemigo(ByVal NpcIndex As Integer, ByVal UserIndex As Integer) As Boolean

    If NpcIndex = 0 Or UserIndex = 0 Then Exit Function

    With NpcList(NpcIndex)

        If .flags.AttackedBy <> vbNullString Then
            EsEnemigo = (UserIndex = NameIndex(.flags.AttackedBy))
            If EsEnemigo Then Exit Function
        End If

        Select Case .flags.AIAlineacion
            Case e_Alineacion.Real
                EsEnemigo = (Status(UserIndex) Mod 2) <> 1

            Case e_Alineacion.Caos
                EsEnemigo = (Status(UserIndex) Mod 2) <> 0

            Case e_Alineacion.ninguna
                EsEnemigo = True
                ' Ok. No hay nada especial para hacer, cualquiera puede ser enemigo!

        End Select

    End With
End Function

Private Function EnRangoVision(ByVal NpcIndex As Integer, ByVal UserIndex As Integer) As Boolean
    Dim userPos As WorldPos
    Dim NpcPos As WorldPos
    Dim Limite_X As Byte, Limite_Y As Byte

    ' Si alguno es cero, devolve false
    If NpcIndex = 0 Or UserIndex = 0 Then Exit Function

    Limite_X = IIf(NpcList(NpcIndex).Distancia <> 0, NpcList(NpcIndex).Distancia, RANGO_VISION_X)
    Limite_Y = IIf(NpcList(NpcIndex).Distancia <> 0, NpcList(NpcIndex).Distancia, RANGO_VISION_Y)

    userPos = UserList(UserIndex).Pos
    NpcPos = NpcList(NpcIndex).Pos

    EnRangoVision = ( _
      (userPos.Map = NpcPos.Map) And _
      (Abs(userPos.X - NpcPos.X) <= Limite_X) And _
      (Abs(userPos.Y - NpcPos.Y) <= Limite_Y) _
    )

End Function

Private Function UsuarioAtacableConMagia(ByVal targetUserIndex As Integer) As Boolean
    If targetUserIndex = 0 Then Exit Function

    With UserList(targetUserIndex)
      UsuarioAtacableConMagia = ( _
        .flags.Muerto = 0 And _
        .flags.invisible = 0 And _
        .flags.Inmunidad = 0 And _
        .flags.Oculto = 0 And _
        .flags.Mimetizado < e_EstadoMimetismo.FormaBichoSinProteccion And _
        Not EsGM(targetUserIndex) And _
        Not .flags.EnConsulta)
    End With

End Function

Private Function UsuarioAtacableConMelee(ByVal NpcIndex As Integer, ByVal targetUserIndex As Integer) As Boolean
    If targetUserIndex = 0 Then Exit Function

    Dim EstaPegadoAlUser As Boolean
    
    With UserList(targetUserIndex)
    
      EstaPegadoAlUser = Distancia(NpcList(NpcIndex).Pos, .Pos) = 1

      UsuarioAtacableConMelee = ( _
        .flags.Muerto = 0 And _
        .flags.Inmunidad = 0 And _
        (EstaPegadoAlUser Or (Not EstaPegadoAlUser And (.flags.invisible + .flags.Oculto) = 0)) And _
        .flags.Mimetizado < e_EstadoMimetismo.FormaBichoSinProteccion And _
        Not EsGM(targetUserIndex) And _
        Not .flags.EnConsulta)
    End With

End Function

