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
        // WhseCreatePick.SetParameter(bo_MDEProcess);  //C54°
        WhseCreatePick.SetWkshPickLine(WkshPickLine);
        //START C54° ---------------------------------
        if bo_MDEProcess then
            WhseCreatePick.UseRequestPage(false);
        //STOP  C54° ---------------------------------
        WhseCreatePick.RunModal;
        //START C54° ---------------------------------
        if bo_MDEProcess then begin
            // WhseCreatePick.GetFilters(lo_re_WhseWorksheetLine);
            Rec.CopyFilters(lo_re_WhseWorksheetLine);
        end;
        //STOP  C54° ---------------------------------
        if WhseCreatePick.GetResultMessage then begin
            Rec.AutofillQtyToHandle(Rec);
            // WhseCreatePick.OpenPick;   //C54°
        end;
        Clear(WhseCreatePick);

        Rec.Reset();
        Rec.SetCurrentKey("Worksheet Template Name", Name, "Location Code", "Sorting Sequence No.");
        Rec.FilterGroup := 2;
        // Rec.SetRange("Worksheet Template Name", "Worksheet Template Name");
        // Rec.SetRange(Name, Name);
        // Rec.SetRange("Location Code", "Location Code");
        Rec.FilterGroup := 0;
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

