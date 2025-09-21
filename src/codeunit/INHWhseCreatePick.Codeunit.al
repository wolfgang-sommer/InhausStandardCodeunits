codeunit 50153 INHWhseCreatePick
{
    // +---------------------------------------------+
    // +                                             +
    // +           Inhaus Handels GmbH               +
    // +                                             +
    // +---------------------------------------------+
    // 
    // ID    Requ.   KZ   Datum     Beschreibung
    // ------------------------------------------------------------
    // C54°          RBI  26.06.19  Anpassung für MDE Lösung

    TableNo = "Whse. Worksheet Line";

    trigger OnRun()
    var
        lo_re_WhseWorksheetLine: Record "Whse. Worksheet Line";
    begin
        WkshPickLine.Copy(Rec);
        WhseCreatePick.fnk_SetParameter(bo_MDEProcess);  //C54°
        WhseCreatePick.SetWkshPickLine(WkshPickLine);
        //START C54° ---------------------------------
        if bo_MDEProcess then
            WhseCreatePick.UseRequestPage(false);
        //STOP  C54° ---------------------------------
        WhseCreatePick.RunModal;
        //START C54° ---------------------------------
        if bo_MDEProcess then begin
            WhseCreatePick.fnk_GetFilters(lo_re_WhseWorksheetLine);
            Rec.CopyFilters(lo_re_WhseWorksheetLine);
        end;
        //STOP  C54° ---------------------------------
        if WhseCreatePick.GetResultMessage then begin
            AutofillQtyToHandle(Rec);
            WhseCreatePick.fnk_OpenPick;   //C54°
        end;
        Clear(WhseCreatePick);

        Reset;
        SetCurrentKey("Worksheet Template Name", Name, "Location Code", "Sorting Sequence No.");
        FilterGroup := 2;
        SetRange("Worksheet Template Name", "Worksheet Template Name");
        SetRange(Name, Name);
        SetRange("Location Code", "Location Code");
        FilterGroup := 0;
    end;

    var
        WkshPickLine: Record "Whse. Worksheet Line";
        WhseCreatePick: Report "Create Pick";
        "+++VAR_Inhaus+++": Integer;
        bo_MDEProcess: Boolean;

    local procedure "+++FNK_Inhaus+++"()
    begin
    end;

    [Scope('Internal')]
    procedure fnk_SetParameter(par_bo_MDEProcess: Boolean)
    begin
        bo_MDEProcess := par_bo_MDEProcess;  //C54°
    end;
}

